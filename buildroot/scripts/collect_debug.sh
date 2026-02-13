#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-unknown}"
MEDIUM="${2:-unknown}"
TS="${3:-$(date +%Y%m%d_%H%M%S)}"
OUTPUT_DIR="${4:-/build/output}"
SDK_DIR="${5:-/build/repos/luckfox-pico}"
WORKSPACE_DIR="${6:-/build}"
ROOTFS_DIR_ARG="${7:-}"

DEST_DIR="$OUTPUT_DIR/debug/${PROFILE}-${MEDIUM}-${TS}"
mkdir -p "$DEST_DIR"

echo "Collecting debug bundle: $DEST_DIR"

{
  echo "profile=$PROFILE"
  echo "medium=$MEDIUM"
  echo "timestamp=$TS"
  echo "output_dir=$OUTPUT_DIR"
  echo "sdk_dir=$SDK_DIR"
  echo "workspace_dir=$WORKSPACE_DIR"
  echo "rootfs_dir_arg=$ROOTFS_DIR_ARG"
} > "$DEST_DIR/meta.txt"

env | sort | grep -E '^(BR2_EXTERNAL|BR2_)' > "$DEST_DIR/env.txt" || true

{
  echo "repo=$WORKSPACE_DIR"
  (cd "$WORKSPACE_DIR" && git rev-parse HEAD && git status --porcelain) || true
  echo
  echo "repo=$SDK_DIR"
  (cd "$SDK_DIR" && git rev-parse HEAD && git status --porcelain) || true
} > "$DEST_DIR/git.txt"

mapfile -t CFGS < <(find "$SDK_DIR" \( -path '*buildroot*/output*/.config' -o -path '*buildroot*/output*/build/.config' \) -type f 2>/dev/null | sort)
if [ "${#CFGS[@]}" -gt 0 ]; then
  printf '%s\n' "${CFGS[@]}" > "$DEST_DIR/buildroot.config.paths.txt"
  cp -f "${CFGS[0]}" "$DEST_DIR/buildroot.config"
  grep -E '^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_PACKAGE_BUSYBOX|BR2_ROOTFS_OVERLAY)=' "${CFGS[0]}" > "$DEST_DIR/buildroot.config.grep.txt" || true
else
  echo "No buildroot .config files found" > "$DEST_DIR/buildroot.config.paths.txt"
fi

TARGET_DIR=""
if [ -n "$ROOTFS_DIR_ARG" ] && [ -d "$ROOTFS_DIR_ARG" ]; then
  TARGET_DIR="$ROOTFS_DIR_ARG"
else
  TARGET_DIR=$(find "$SDK_DIR" -type d -path '*buildroot*/output*/target' 2>/dev/null | head -n 1 || true)
fi

if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ]; then
  echo "$TARGET_DIR" > "$DEST_DIR/target.path.txt"
  (cd "$TARGET_DIR" && find . -type f -printf '%s %p\n' | sort -n) > "$DEST_DIR/target.manifest.txt"
else
  echo "target directory not found" > "$DEST_DIR/target.path.txt"
fi

IMAGES_REPORT="$DEST_DIR/images.report.txt"
: > "$IMAGES_REPORT"

while IFS= read -r img; do
  [ -f "$img" ] || continue
  {
    echo "=== $img ==="
    ls -l "$img" || true
    file "$img" || true
    sha256sum "$img" || true
    echo
  } >> "$IMAGES_REPORT"
done < <(find "$SDK_DIR" -type f \( -name 'rootfs.img' -o -name 'boot.img' -o -name 'idblock.img' -o -name 'uboot.img' -o -name 'trust.img' -o -name 'update.img' -o -name 'download.bin' \) 2>/dev/null | sort)

NAND_ROOTFS=$(find "$SDK_DIR" -type f -name 'rootfs.img' -print0 2>/dev/null | xargs -0 -r file | grep -i 'UBI image' | head -n 1 | cut -d: -f1 || true)
if [ -n "$NAND_ROOTFS" ]; then
  {
    echo "selected_rootfs_img=$NAND_ROOTFS"
    file "$NAND_ROOTFS" || true
  } > "$DEST_DIR/rootfs.selected.txt"
else
  echo "No UBI rootfs.img found" > "$DEST_DIR/rootfs.selected.txt"
fi

echo "Debug bundle complete: $DEST_DIR"
