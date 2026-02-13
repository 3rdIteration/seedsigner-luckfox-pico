#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-unknown}"
MEDIUM="${2:-unknown}"
TS="${3:-$(date +%Y%m%d_%H%M%S)}"
OUTPUT_DIR="${4:-/build/output}"
SDK_DIR="${5:-/build/repos/luckfox-pico}"
WORKSPACE_DIR="${6:-/build}"
ROOTFS_DIR_ARG="${7:-}"

DEST_DIR="$OUTPUT_DIR"
DEBUG_DIR="$OUTPUT_DIR/debug/${PROFILE}-${MEDIUM}-${TS}"
mkdir -p "$DEST_DIR" "$DEBUG_DIR"

echo "Collecting debug bundle: $DEST_DIR"

write_both() {
  local src="$1"
  local base="$2"
  cp -f "$src" "$DEST_DIR/$base"
  cp -f "$src" "$DEBUG_DIR/$base"
}

{
  echo "profile=$PROFILE"
  echo "medium=$MEDIUM"
  echo "timestamp=$TS"
  echo "output_dir=$OUTPUT_DIR"
  echo "sdk_dir=$SDK_DIR"
  echo "workspace_dir=$WORKSPACE_DIR"
  echo "rootfs_dir_arg=$ROOTFS_DIR_ARG"
} > "$DEBUG_DIR/meta.txt"

env | sort | grep -E '^(BR2_EXTERNAL|BR2_)' > "$DEST_DIR/env.txt" || true
cp -f "$DEST_DIR/env.txt" "$DEBUG_DIR/env.txt"

{
  echo "repo=$WORKSPACE_DIR"
  (cd "$WORKSPACE_DIR" && git rev-parse HEAD && git status --porcelain) || true
  echo
  echo "repo=$SDK_DIR"
  (cd "$SDK_DIR" && git rev-parse HEAD && git status --porcelain) || true
} > "$DEST_DIR/git.txt"
cp -f "$DEST_DIR/git.txt" "$DEBUG_DIR/git.txt"

mapfile -t CFGS < <(find "$SDK_DIR" \( -path '*buildroot*/output*/.config' -o -path '*buildroot*/output*/build/.config' \) -type f 2>/dev/null | sort)
if [ "${#CFGS[@]}" -gt 0 ]; then
  printf '%s\n' "${CFGS[@]}" > "$DEST_DIR/buildroot.config.paths.txt"
  cp -f "${CFGS[0]}" "$DEST_DIR/buildroot.config"
  grep -E '^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_PACKAGE_BUSYBOX|BR2_ROOTFS_OVERLAY)=' "${CFGS[0]}" > "$DEST_DIR/buildroot.config.grep.txt" || true
else
  echo "No buildroot .config files found" > "$DEST_DIR/buildroot.config.paths.txt"
  : > "$DEST_DIR/buildroot.config.grep.txt"
fi
cp -f "$DEST_DIR/buildroot.config.paths.txt" "$DEBUG_DIR/buildroot.config.paths.txt"
[ -f "$DEST_DIR/buildroot.config" ] && cp -f "$DEST_DIR/buildroot.config" "$DEBUG_DIR/buildroot.config"
cp -f "$DEST_DIR/buildroot.config.grep.txt" "$DEBUG_DIR/buildroot.config.grep.txt"

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
  : > "$DEST_DIR/target.manifest.txt"
fi
cp -f "$DEST_DIR/target.path.txt" "$DEBUG_DIR/target.path.txt"
cp -f "$DEST_DIR/target.manifest.txt" "$DEBUG_DIR/target.manifest.txt"

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
cp -f "$IMAGES_REPORT" "$DEBUG_DIR/images.report.txt"

ROOTFS_UBI=$(find "$SDK_DIR" -name rootfs.img -print0 | xargs -0 -I{} sh -c 'file "$1" | grep -qi "UBI image" && echo "$1"' _ {} | head -n1 || true)
if [ "$MEDIUM" = "nand" ]; then
  if [ -z "$ROOTFS_UBI" ]; then
    echo "No UBI rootfs.img found for NAND build" >&2
    exit 40
  fi
  cp -f "$ROOTFS_UBI" "$DEST_DIR/rootfs.img"
  {
    echo "selected_rootfs_img=$ROOTFS_UBI"
    file "$ROOTFS_UBI" || true
  } > "$DEST_DIR/rootfs.selected.txt"
else
  ROOTFS_ANY=$(find "$SDK_DIR" -type f -name rootfs.img | head -n1 || true)
  if [ -n "$ROOTFS_ANY" ]; then
    cp -f "$ROOTFS_ANY" "$DEST_DIR/rootfs.img"
    {
      echo "selected_rootfs_img=$ROOTFS_ANY"
      file "$ROOTFS_ANY" || true
    } > "$DEST_DIR/rootfs.selected.txt"
  else
    echo "No rootfs.img found" > "$DEST_DIR/rootfs.selected.txt"
  fi
fi
cp -f "$DEST_DIR/rootfs.selected.txt" "$DEBUG_DIR/rootfs.selected.txt"

echo "Debug bundle complete: $DEST_DIR"
