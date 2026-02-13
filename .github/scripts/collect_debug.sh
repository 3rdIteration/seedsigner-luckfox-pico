#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:?profile required}"
MEDIUM="${2:?medium required}"
OUTDIR="${3:?outdir required}"

mkdir -p "$OUTDIR"

{
  echo "profile=$PROFILE"
  echo "medium=$MEDIUM"
  echo "pwd=$(pwd)"
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUTDIR/run.txt"

env | sort | grep -E '^(BR2_EXTERNAL|BR2_)' > "$OUTDIR/env.txt" || true

{
  echo "top_repo_sha=$(git rev-parse HEAD 2>/dev/null || true)"
  echo "top_repo_status:"
  git status --porcelain 2>/dev/null || true
} > "$OUTDIR/git.txt"

if git lfs version >/dev/null 2>&1; then
  {
    echo "git-lfs-installed=yes"
    git lfs env 2>/dev/null || true
  } > "$OUTDIR/git-lfs.txt"
else
  echo "git-lfs-installed=no" > "$OUTDIR/git-lfs.txt"
fi

# Inspect persistent SDK volume via the built container image.
# This is where the SDK build tree lives during build.sh runs.
docker run --rm \
  -v seedsigner-repos:/repos:ro \
  -v "$OUTDIR":/out \
  seedsigner-builder \
  bash -lc '
set -euo pipefail
SDK=/repos/luckfox-pico
SEEDSIGNER=/repos/seedsigner
SEEDSIGNER_OS=/repos/seedsigner-os

echo "sdk_repo_sha=$(git -C "$SDK" rev-parse HEAD 2>/dev/null || true)" >> /out/git.txt
echo "sdk_repo_status:" >> /out/git.txt
git -C "$SDK" status --porcelain >> /out/git.txt 2>/dev/null || true
echo "seedsigner_repo_sha=$(git -C \"$SEEDSIGNER\" rev-parse HEAD 2>/dev/null || true)" >> /out/git.txt
echo "seedsigner_os_repo_sha=$(git -C \"$SEEDSIGNER_OS\" rev-parse HEAD 2>/dev/null || true)" >> /out/git.txt

echo "--- sdk .BoardConfig.mk ---" > /out/boardconfig.txt
if [[ -f "$SDK/.BoardConfig.mk" ]]; then
  grep -E "^(export RK_UBOOT_DEFCONFIG|export RK_KERNEL_DEFCONFIG|export RK_BUILDROOT_CFG|export RK_BOOTARGS_CMA_SIZE|export RK_BOOT_MEDIUM|export RK_TARGET_PRODUCT)=" "$SDK/.BoardConfig.mk" >> /out/boardconfig.txt || true
else
  echo ".BoardConfig.mk missing" >> /out/boardconfig.txt
fi

env | sort | grep -E "^(BR2_EXTERNAL|BR2_)" > /out/container-br2-env.txt || true

CFG=$(find "$SDK" \( -path "*buildroot*/output*/.config" -o -path "*buildroot*/output*/build/.config" \) -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n 1 | cut -d" " -f2- || true)
if [[ -n "$CFG" && -f "$CFG" ]]; then
  cp -f "$CFG" /out/buildroot.config
  grep -E "^(BR2_PACKAGE_EUDEV|BR2_PACKAGE_KMOD|BR2_PACKAGE_UTIL_LINUX|BR2_PACKAGE_UTIL_LINUX_LIBBLKID|BR2_PACKAGE_BUSYBOX|BR2_ROOTFS_OVERLAY)=" "$CFG" > /out/buildroot.config.grep.txt || true
else
  echo "no buildroot .config found" > /out/buildroot.config.grep.txt
fi

if [[ -f "$SDK/sysdrv/source/buildroot-2023.02.6/configs/luckfox_pico_defconfig" ]]; then
  cp -f "$SDK/sysdrv/source/buildroot-2023.02.6/configs/luckfox_pico_defconfig" /out/luckfox_pico_defconfig
fi

TARGET=$(find "$SDK" -type d -path "*buildroot*/output*/target" -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n 1 | cut -d" " -f2- || true)
if [[ -n "$TARGET" && -d "$TARGET" ]]; then
  (cd "$TARGET" && find . -type f -printf "%s %p\n" | sort -n) > /out/target.manifest.txt
else
  echo "no target dir found" > /out/target.manifest.txt
fi

REPORT=/out/images.report.txt
: > "$REPORT"
for name in rootfs.img boot.img idblock.img uboot.img trust.img update.img; do
  while IFS= read -r p; do
    [[ -f "$p" ]] || continue
    echo "=== $name ===" >> "$REPORT"
    echo "path=$p" >> "$REPORT"
    ls -l "$p" >> "$REPORT" 2>&1 || true
    file "$p" >> "$REPORT" 2>&1 || true
    sha256sum "$p" >> "$REPORT" 2>&1 || true
    echo >> "$REPORT"
  done < <(find "$SDK" -type f -name "$name" 2>/dev/null)
done

if [[ "$MEDIUM" == "nand" ]]; then
  ROOTFS_NAND=$(find "$SDK" -type f -name rootfs.img -print0 | xargs -0 -I{} sh -c "file \"{}\"" | grep -i "UBI image" | sed "s/:.*//" | head -n 1 || true)
  if [[ -z "$ROOTFS_NAND" ]]; then
    ROOTFS_NAND=$(find "$SDK" -type f -name rootfs.img | head -n 1 || true)
  fi
  if [[ -n "$ROOTFS_NAND" && -f "$ROOTFS_NAND" ]]; then
    cp -f "$ROOTFS_NAND" /out/rootfs.img
    {
      echo "selected_rootfs_img=$ROOTFS_NAND"
      file "$ROOTFS_NAND" || true
      sha256sum "$ROOTFS_NAND" || true
    } > /out/selected_rootfs.txt
  else
    echo "selected_rootfs_img=NOT_FOUND" > /out/selected_rootfs.txt
  fi
fi
'

# Also record image metadata from workspace outputs for cross-check.
{
  echo "workspace image scan:"
  find "$GITHUB_WORKSPACE" -type f \( -name 'rootfs.img' -o -name 'boot.img' -o -name 'update.img' -o -name 'idblock.img' -o -name 'uboot.img' -o -name 'trust.img' \) 2>/dev/null || true
} > "$OUTDIR/workspace-images.txt"

if [[ "$MEDIUM" == "nand" ]]; then
  if [[ -f "$OUTDIR/selected_rootfs.txt" ]]; then
    echo "Selected NAND rootfs info:"
    cat "$OUTDIR/selected_rootfs.txt"
  fi
fi
