#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${1:-/workspace}"
SDK_ROOT="${2:-/build/repos/luckfox-pico}"

FRAGMENT_SRC="$WORKSPACE_ROOT/buildroot/configs/seedsigner_required.fragment"
OVERLAY_SRC="$WORKSPACE_ROOT/buildroot/overlay"

if [[ ! -f "$FRAGMENT_SRC" ]]; then
  echo "ERROR: required fragment not found: $FRAGMENT_SRC"
  exit 90
fi
if [[ ! -d "$OVERLAY_SRC" ]]; then
  echo "ERROR: required overlay dir not found: $OVERLAY_SRC"
  exit 91
fi

BR_DIR=$(find "$SDK_ROOT" -type d -path '*/sysdrv/source/buildroot/buildroot-*' | sort | head -n1 || true)
if [[ -z "$BR_DIR" || ! -d "$BR_DIR" ]]; then
  echo "ERROR: could not locate Buildroot directory under $SDK_ROOT"
  exit 92
fi

echo "Using BR_DIR=$BR_DIR"
cd "$BR_DIR"

make luckfox_pico_defconfig

cp -f "$FRAGMENT_SRC" "$BR_DIR/seedsigner_required.fragment"
rm -rf "$BR_DIR/seedsigner_overlay"
mkdir -p "$BR_DIR/seedsigner_overlay"
cp -a "$OVERLAY_SRC"/. "$BR_DIR/seedsigner_overlay/"
chmod +x "$BR_DIR/seedsigner_overlay/etc/init.d/"S* 2>/dev/null || true

if [[ -x "$BR_DIR/scripts/kconfig/merge_config.sh" ]]; then
  "$BR_DIR/scripts/kconfig/merge_config.sh" -m "$BR_DIR/.config" "$BR_DIR/seedsigner_required.fragment"
else
  cat "$BR_DIR/seedsigner_required.fragment" >> "$BR_DIR/.config"
fi

sed -i '/^BR2_ROOTFS_OVERLAY=/d' "$BR_DIR/.config"
echo "BR2_ROOTFS_OVERLAY=\"$BR_DIR/seedsigner_overlay\"" >> "$BR_DIR/.config"

make olddefconfig

grep -q '^BR2_PACKAGE_EUDEV=y' "$BR_DIR/.config" || { echo "EUDEV not enabled"; exit 101; }
grep -q '^BR2_PACKAGE_KMOD=y' "$BR_DIR/.config" || { echo "KMOD not enabled"; exit 102; }
grep -q '^BR2_PACKAGE_UTIL_LINUX=y' "$BR_DIR/.config" || { echo "util-linux not enabled"; exit 103; }
grep -q '^BR2_PACKAGE_UTIL_LINUX_LIBBLKID=y' "$BR_DIR/.config" || { echo "libblkid not enabled"; exit 104; }
grep -q '^BR2_ROOTFS_OVERLAY="' "$BR_DIR/.config" || { echo "overlay not set"; exit 105; }
grep -q '^BR2_ROOTFS_OVERLAY="[^"]\+"' "$BR_DIR/.config" || { echo "overlay empty"; exit 106; }

echo "--- Final key Buildroot options ---"
grep -E '^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_ROOTFS_OVERLAY)=' "$BR_DIR/.config"
