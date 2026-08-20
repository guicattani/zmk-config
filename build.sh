#!/usr/bin/env bash
# Local build of the ZMK firmware for the Sofle Choc Pro BT.
#
# Mirrors what GitHub Actions does (build.yaml + .github/workflows/build.yml),
# but only for the sofle_choc_pro boards, using the same Docker image.
#
# Prereqs: docker (daemon running).
# First run downloads the toolchain image + ZMK/Zephyr (~2 GB) and takes a
# while; later runs are cached in .build/.
#
# Usage:
#   ./build.sh            build left + right firmware + settings_reset
#   ./build.sh left       build left half only
#   ./build.sh right      build right half only
#   ./build.sh clean      remove .build/ and firmware/
#
# Output: firmware/*.uf2 (drag onto each half in bootloader mode).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${ZMK_BUILD_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
BUILD_DIR="${ZMK_BUILD_DIR:-$REPO_DIR/.build}"
FIRMWARE_DIR="$REPO_DIR/firmware"

TARGET="${1:-all}"
case "$TARGET" in
  all|left|right) ;;
  clean)
    rm -rf "$BUILD_DIR" "$FIRMWARE_DIR"
    echo "Cleaned build workspace."
    exit 0
    ;;
  *)
    echo "Usage: $0 {all|left|right|clean}" >&2
    exit 1
    ;;
esac

mkdir -p "$BUILD_DIR/home" "$FIRMWARE_DIR"

docker run --rm \
  -e TARGET="$TARGET" \
  -e HOME=/build/home \
  -v "$REPO_DIR":/workspace:ro \
  -v "$BUILD_DIR":/build \
  "$IMAGE" \
  bash -c '
    set -euo pipefail
    cd /build

    # First run: set up the west workspace (ZMK + Zephyr). Cached afterwards.
    if [ ! -d .west ]; then
      rm -rf config
      cp -R /workspace/config ./config
      west init -l ./config
      west update --fetch-opt=--filter=tree:0
      west zephyr-export
    else
      rm -rf config
      cp -R /workspace/config ./config
    fi

    build() {
      local board=$1 shield=$2 dir=$3 snippet=$4 cmake_args=${5:-}
      echo "==> $board${shield:+ + $shield}"
      west build -s zmk/app -d "/build/$dir" -b "$board" \
        -S "$snippet" -- \
        -DZMK_CONFIG=/build/config \
        -DSHIELD="$shield" \
        -DZMK_EXTRA_MODULES=/workspace \
        $cmake_args
    }

    if [ "$TARGET" = "all" ] || [ "$TARGET" = "left" ]; then
      build sofle_choc_pro_left  nice_view_disp build/left        studio-rpc-usb-uart "-DCONFIG_ZMK_STUDIO=y"
      build sofle_choc_pro_left  settings_reset build/left-reset  studio-rpc-usb-uart
    fi
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "right" ]; then
      build sofle_choc_pro_right nice_view_disp build/right       studio-rpc-usb-uart
      build sofle_choc_pro_right settings_reset build/right-reset studio-rpc-usb-uart
    fi
  '

# The container runs as root; give the artifacts back to the local user.
if [ ! -w "$BUILD_DIR" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$BUILD_DIR" 2>/dev/null || true
fi

collect() { # $1 = build subdir, $2 = output filename
  local src="$BUILD_DIR/$1/zephyr/zmk.uf2"
  if [ -f "$src" ]; then
    cp "$src" "$FIRMWARE_DIR/$2"
    echo "  $2"
  fi
}

echo "Firmware in $FIRMWARE_DIR/:"
collect build/left        sofle_choc_pro_left.uf2
collect build/right       sofle_choc_pro_right.uf2
collect build/left-reset  sofle_choc_pro_left_settings_reset.uf2
collect build/right-reset sofle_choc_pro_right_settings_reset.uf2
