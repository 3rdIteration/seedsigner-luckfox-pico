#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
SDK_ROOT="${SDK_ROOT:-/build/repos/luckfox-pico}"
DEFCONFIG_NAME="${DEFCONFIG_NAME:-luckfox_pico_defconfig}"

FRAGMENT_SRC="$WORKSPACE_ROOT/buildroot/configs/seedsigner_required.fragment"
OVERLAY_SRC="$WORKSPACE_ROOT/buildroot/overlay"

if [[ ! -f "$FRAGMENT_SRC" ]]; then
  echo "Missing fragment: $FRAGMENT_SRC"
  exit 90
fi
if [[ ! -d "$OVERLAY_SRC" ]]; then
  echo "Missing overlay dir: $OVERLAY_SRC"
  exit 91
fi

BR_DIR=$(find "$SDK_ROOT" -type d -path '*/sysdrv/source/buildroot/buildroot-*' | sort | head -n1)
if [[ -z "$BR_DIR" || ! -d "$BR_DIR" ]]; then
  echo "Unable to locate Buildroot dir under $SDK_ROOT"
  exit 92
fi

echo "Using Buildroot dir: $BR_DIR"
cd "$BR_DIR"

make "$DEFCONFIG_NAME"

cp "$FRAGMENT_SRC" "$BR_DIR/seedsigner_required.fragment"
rm -rf "$BR_DIR/seedsigner_overlay"
mkdir -p "$BR_DIR/seedsigner_overlay"
cp -a "$OVERLAY_SRC"/. "$BR_DIR/seedsigner_overlay/"
chmod +x "$BR_DIR/seedsigner_overlay/etc/init.d/S10udev" || true
chmod +x "$BR_DIR/seedsigner_overlay/etc/init.d/S50usbdevice" || true
chmod +x "$BR_DIR/seedsigner_overlay/etc/init.d/S99_auto_reboot" || true

if [[ -f "$BR_DIR/scripts/kconfig/merge_config.sh" ]]; then
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

grep -E '^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_ROOTFS_OVERLAY)=' "$BR_DIR/.config"
