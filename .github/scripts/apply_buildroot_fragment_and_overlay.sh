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

mapfile -t BUILDROOT_DIRS < <(find "$SDK_ROOT" -type d -path '*/sysdrv/source/buildroot/buildroot-*' 2>/dev/null | sort)
BR_DIR="${BUILDROOT_DIRS[0]:-}"
if [[ -z "$BR_DIR" || ! -d "$BR_DIR" ]]; then
  echo "Unable to locate Buildroot dir under $SDK_ROOT"
  exit 92
fi

echo "Using Buildroot dir: $BR_DIR"
cd "$BR_DIR"

UDEV_SYMBOL=""
if grep -Rqs '^config BR2_PACKAGE_EUDEV$' package; then
  UDEV_SYMBOL="BR2_PACKAGE_EUDEV"
elif grep -Rqs '^config BR2_PACKAGE_HAS_UDEV$' package system; then
  UDEV_SYMBOL="BR2_PACKAGE_HAS_UDEV"
fi

make "$DEFCONFIG_NAME"

cp "$FRAGMENT_SRC" "$BR_DIR/seedsigner_required.fragment"

# Force dynamic device management to eudev so udev userspace actually lands in rootfs.
# Remove any existing device creation and eudev lines to avoid duplicates/conflicts
sed -i \
  -e '/^BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=/d' \
  -e '/^# BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV is not set/d' \
  -e '/^BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_MDEV=/d' \
  -e '/^# BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_MDEV is not set/d' \
  -e '/^BR2_PACKAGE_EUDEV=/d' \
  "$BR_DIR/seedsigner_required.fragment"

# Always ensure BR2_PACKAGE_EUDEV is set (required for DYNAMIC_EUDEV device creation)
echo "BR2_PACKAGE_EUDEV=y" >> "$BR_DIR/seedsigner_required.fragment"

cat >> "$BR_DIR/seedsigner_required.fragment" <<'FRAG'
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
# BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_MDEV is not set
FRAG

rm -rf "$BR_DIR/seedsigner_overlay"
mkdir -p "$BR_DIR/seedsigner_overlay"
cp -a "$OVERLAY_SRC"/. "$BR_DIR/seedsigner_overlay/"
chmod +x "$BR_DIR/seedsigner_overlay/etc/init.d/S10udev" || true
chmod +x "$BR_DIR/seedsigner_overlay/etc/init.d/S50usbdevice" || true
chmod +x "$BR_DIR/seedsigner_overlay/etc/init.d/S99_auto_reboot" || true

MERGE_SCRIPT=""
if [[ -f "$BR_DIR/scripts/kconfig/merge_config.sh" ]]; then
  MERGE_SCRIPT="$BR_DIR/scripts/kconfig/merge_config.sh"
elif [[ -f "$BR_DIR/support/kconfig/merge_config.sh" ]]; then
  MERGE_SCRIPT="$BR_DIR/support/kconfig/merge_config.sh"
fi

if [[ -n "$MERGE_SCRIPT" ]]; then
  "$MERGE_SCRIPT" -m "$BR_DIR/.config" "$BR_DIR/seedsigner_required.fragment"
else
  cat "$BR_DIR/seedsigner_required.fragment" >> "$BR_DIR/.config"
fi

sed -i '/^BR2_ROOTFS_OVERLAY=/d' "$BR_DIR/.config"
echo "BR2_ROOTFS_OVERLAY=\"$BR_DIR/seedsigner_overlay\"" >> "$BR_DIR/.config"

make olddefconfig

# Verify that eudev is enabled (required for BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV)
grep -q '^BR2_PACKAGE_EUDEV=y' "$BR_DIR/.config" || { echo "BR2_PACKAGE_EUDEV not enabled"; exit 101; }
grep -q '^BR2_PACKAGE_KMOD=y' "$BR_DIR/.config" || { echo "KMOD not enabled"; exit 102; }
grep -q '^BR2_PACKAGE_UTIL_LINUX=y' "$BR_DIR/.config" || { echo "util-linux not enabled"; exit 103; }
grep -q '^BR2_PACKAGE_UTIL_LINUX_LIBBLKID=y' "$BR_DIR/.config" || { echo "libblkid not enabled"; exit 104; }
grep -q '^BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y' "$BR_DIR/.config" || { echo "dynamic eudev /dev backend not enabled"; exit 107; }
grep -q '^BR2_ROOTFS_OVERLAY="' "$BR_DIR/.config" || { echo "overlay not set"; exit 105; }

grep -E '^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_HAS_UDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV|BR2_ROOTFS_OVERLAY)=' "$BR_DIR/.config"
