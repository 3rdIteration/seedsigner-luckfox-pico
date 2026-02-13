#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:?profile required}"
MEDIUM="${2:?medium required}"
ARTIFACT_DIR="${3:?artifact dir required}"
WORKSPACE="${4:-$PWD}"
IMAGE_NAME="${5:-seedsigner-builder}"
VOLUME_NAME="${6:-seedsigner-repos}"

mkdir -p "$ARTIFACT_DIR"

{
  echo "profile=$PROFILE"
  echo "medium=$MEDIUM"
  echo "workspace=$WORKSPACE"
  echo "image_name=$IMAGE_NAME"
  echo "volume_name=$VOLUME_NAME"
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$ARTIFACT_DIR/meta.txt"

env | sort | grep -E '^(BR2_EXTERNAL|BR2_)' > "$ARTIFACT_DIR/env.txt" || true

{
  echo "[workspace]"
  (cd "$WORKSPACE" && git rev-parse HEAD && git status --porcelain) || true
  echo ""
  echo "[workspace git-lfs]"
  (cd "$WORKSPACE" && git lfs version && git lfs ls-files | head -n 50) || echo "git-lfs not available or no lfs files"
} > "$ARTIFACT_DIR/git.txt"

if [ -f "$WORKSPACE/buildroot/configs/luckfox_pico_defconfig" ]; then
  cp -f "$WORKSPACE/buildroot/configs/luckfox_pico_defconfig" "$ARTIFACT_DIR/expected.luckfox_pico_defconfig"
  {
    echo "EXPECTED_DEFCONFIG=$WORKSPACE/buildroot/configs/luckfox_pico_defconfig"
    grep -E "^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_PACKAGE_BUSYBOX|BR2_ROOTFS_OVERLAY)=" "$WORKSPACE/buildroot/configs/luckfox_pico_defconfig" || true
    grep -E "^# (BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_PACKAGE_BUSYBOX|BR2_ROOTFS_OVERLAY) is not set" "$WORKSPACE/buildroot/configs/luckfox_pico_defconfig" || true
  } > "$ARTIFACT_DIR/expected.defconfig.grep.txt"
fi

# Extract build debug details from the same docker volume where the SDK repos live.
docker run --rm \
  -v "$VOLUME_NAME:/build/repos" \
  -v "$WORKSPACE:$WORKSPACE" \
  -e ARTIFACT_DIR="$ARTIFACT_DIR" \
  -e PROFILE="$PROFILE" \
  -e MEDIUM="$MEDIUM" \
  "$IMAGE_NAME" /bin/bash -lc '
set -euo pipefail
SDK_ROOT=/build/repos/luckfox-pico
mkdir -p "$ARTIFACT_DIR"

{
  echo "[luckfox-pico]"
  (cd "$SDK_ROOT" && git rev-parse HEAD && git status --porcelain) || true
} >> "$ARTIFACT_DIR/git.txt"

find "$SDK_ROOT" -type f \( -path "*buildroot*/output*/.config" -o -path "*buildroot*/output*/build/.config" \) 2>/dev/null | sort > "$ARTIFACT_DIR/buildroot.config.paths.txt" || true

CONFIG_PATH=$(while IFS= read -r p; do [ -f "$p" ] && echo "$p"; done < "$ARTIFACT_DIR/buildroot.config.paths.txt" | xargs -r ls -1t | head -n1 || true)
if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ]; then
  cp -f "$CONFIG_PATH" "$ARTIFACT_DIR/buildroot.config"
  {
    echo "CONFIG_PATH=$CONFIG_PATH"
    grep -E "^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_PACKAGE_BUSYBOX|BR2_ROOTFS_OVERLAY)=" "$CONFIG_PATH" || true
    grep -E "^# (BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_PACKAGE_BUSYBOX|BR2_ROOTFS_OVERLAY) is not set" "$CONFIG_PATH" || true
  } > "$ARTIFACT_DIR/buildroot.config.grep.txt"
  {
    echo "buildroot.config sha256:"
    sha256sum "$ARTIFACT_DIR/buildroot.config" || true
    if [ -f "$ARTIFACT_DIR/expected.luckfox_pico_defconfig" ]; then
      echo "expected defconfig sha256:"
      sha256sum "$ARTIFACT_DIR/expected.luckfox_pico_defconfig" || true
    fi
  } > "$ARTIFACT_DIR/config.sha256.txt"
else
  echo "No Buildroot .config found" > "$ARTIFACT_DIR/buildroot.config.grep.txt"
fi

find "$SDK_ROOT" -type d -path "*buildroot*/output*/target" 2>/dev/null | sort > "$ARTIFACT_DIR/target.paths.txt" || true
TARGET_DIR=$(while IFS= read -r p; do [ -d "$p" ] && echo "$p"; done < "$ARTIFACT_DIR/target.paths.txt" | xargs -r ls -1dt | head -n1 || true)
if [ -n "${TARGET_DIR:-}" ] && [ -d "$TARGET_DIR" ]; then
  {
    echo "TARGET_DIR=$TARGET_DIR"
    (cd "$TARGET_DIR" && find . -type f -printf "%s %p\n" | sort -n)
  } > "$ARTIFACT_DIR/target.manifest.txt"
else
  echo "No Buildroot target directory found" > "$ARTIFACT_DIR/target.manifest.txt"
fi

find "$SDK_ROOT" -type f -name "*.img" 2>/dev/null | sort > "$ARTIFACT_DIR/image.paths.txt" || true

{
  echo "Image report for ${PROFILE}-${MEDIUM}"
  while IFS= read -r img; do
    [ -f "$img" ] || continue
    echo ""
    echo "=== $img ==="
    ls -l "$img" || true
    file "$img" || true
    sha256sum "$img" || true
  done < "$ARTIFACT_DIR/image.paths.txt"
} > "$ARTIFACT_DIR/images.report.txt"

SELECTED_ROOTFS=""
if [ "$MEDIUM" = "nand" ]; then
  SELECTED_ROOTFS=$(while IFS= read -r p; do [ -f "$p" ] || continue; file "$p" 2>/dev/null | grep -qi "UBI image" && echo "$p"; done < "$ARTIFACT_DIR/image.paths.txt" | grep "/rootfs.img$" | head -n1 || true)
fi
if [ -z "$SELECTED_ROOTFS" ]; then
  SELECTED_ROOTFS=$(grep "/rootfs.img$" "$ARTIFACT_DIR/image.paths.txt" | head -n1 || true)
fi

if [ "$MEDIUM" = "nand" ] && { [ -z "$SELECTED_ROOTFS" ] || ! file "$SELECTED_ROOTFS" | grep -qi "UBI image"; }; then
  echo "ERROR: No UBI rootfs.img produced for NAND build" > "$ARTIFACT_DIR/selected_rootfs_report.txt"
  exit 120
fi

echo "$SELECTED_ROOTFS" > "$ARTIFACT_DIR/selected_rootfs_img.txt"

if [ -n "$SELECTED_ROOTFS" ] && [ -f "$SELECTED_ROOTFS" ]; then
  cp -f "$SELECTED_ROOTFS" "$ARTIFACT_DIR/rootfs.img"
fi

{
  echo "Selected rootfs image: ${SELECTED_ROOTFS:-<none>}"
  if [ -n "$SELECTED_ROOTFS" ] && [ -f "$SELECTED_ROOTFS" ]; then
    ls -l "$SELECTED_ROOTFS"
    file "$SELECTED_ROOTFS" || true
    sha256sum "$SELECTED_ROOTFS" || true
  fi
} > "$ARTIFACT_DIR/selected_rootfs_report.txt"
'

echo "Debug bundle collected at: $ARTIFACT_DIR"
