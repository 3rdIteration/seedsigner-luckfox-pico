# Buildroot Rust Toolchain Cache

This directory is a placeholder for the pre-built Rust cross-compilation
toolchain for the `armv7-unknown-linux-uclibceabihf` target used by all
LuckFox Pico variants.

## Why?

Building Rust from source for a uclibc Tier 3 target takes **~2 hours** on
GitHub Actions runners. Since all five build variants (Mini SD, Mini NAND,
Pro\_Max SD, Pro\_Max NAND, Pi eMMC) use the **identical** Rust host toolchain,
caching the built toolchain avoids rebuilding it in every CI job.

## How It Works

The toolchain tarball (`rust-toolchain.tar.zst`, ~80–120 MB) is hosted as a
**GitHub Release asset** on this repository under the `rust-toolchain` tag.
No Git LFS or large files in the repo are needed.

During a build, the scripts **download** the tarball and extract it:

```bash
curl -fSL -o /tmp/rust-toolchain.tar.zst \
  https://github.com/3rdIteration/seedsigner-luckfox-pico/releases/download/rust-toolchain/rust-toolchain.tar.zst
tar --zstd -xf /tmp/rust-toolchain.tar.zst -C "$BUILDROOT_DIR/output"
```

Stamp files are created so buildroot skips the `host-rust`, `host-rust-bin`,
and `host-rustc` packages entirely. This saves ~2 hours per build.

If the download fails or `--build-rust-from-source` is set, Rust is built
from source as usual.

## Updating the Cached Toolchain

When the Rust version changes in the buildroot defconfig or the uclibc patches
are updated:

1. Trigger a CI build with **"Build Rust from source"** set to `true` (or run
   locally with `--build-rust-from-source`).
2. CI automatically uploads the new tarball to the `rust-toolchain` release.
3. *(Manual alternative)* Download the `rust-toolchain-cache-*` artifact and
   upload it manually:
   ```bash
   gh release upload rust-toolchain rust-toolchain.tar.zst --clobber \
     --repo 3rdIteration/seedsigner-luckfox-pico
   ```

## Build Script Flags

| Script | Flag |
|--------|------|
| GitHub Actions | `build_rust_from_source: true` (workflow\_dispatch input) |
| `build-local.sh` | `--build-rust-from-source` |
| `os-build.sh` | `BUILD_RUST_FROM_SOURCE=1` (environment variable) |

## Overriding the Download URL

For forks or custom toolchains, set `RUST_TOOLCHAIN_REPO_URL` before running
the local build scripts:

```bash
export RUST_TOOLCHAIN_REPO_URL=https://github.com/youruser/yourrepo
./buildroot/build-local.sh
```

## Tarball Contents

```
output/host/bin/rustc              # Rust compiler (x86_64 host)
output/host/bin/cargo              # Cargo package manager
output/host/bin/rustdoc            # Documentation tool
output/host/lib/rustlib/           # Target libraries
  armv7-unknown-linux-uclibceabihf/  # uclibc ARM target std
  x86_64-unknown-linux-gnu/          # Host std
  ...
```

Plus buildroot stamp files that signal package build completion.
