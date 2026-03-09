# Buildroot Rust Toolchain Cache

This directory stores a pre-built Rust cross-compilation toolchain for the
`armv7-unknown-linux-uclibceabihf` target used by all LuckFox Pico variants.

## Why?

Building Rust from source for a uclibc Tier 3 target takes **~2 hours** on
GitHub Actions runners. Since all five build variants (Mini SD, Mini NAND,
Pro\_Max SD, Pro\_Max NAND, Pi eMMC) use the **identical** Rust host toolchain,
caching the built toolchain avoids rebuilding it in every CI job.

## How Caching Works

### GitHub Actions (CI)

The workflow uses **`actions/cache`** to persist the Rust toolchain tarball
(`rust-toolchain.tar.zst`) across CI runs:

- **Cache hit**: The tarball is restored from `actions/cache`, extracted into
  the buildroot output directory, and stamp files are created so buildroot
  skips the `host-rust`, `host-rust-bin`, and `host-rustc` packages. Saves ~2h.

- **Cache miss** (first build or after defconfig changes): Rust is built from
  source. After the build, the toolchain is packaged as `rust-toolchain.tar.zst`
  and `actions/cache` automatically saves it for future runs.

The cache key is derived from the defconfig hash, so it automatically
invalidates when the Rust configuration changes.

### Local / Docker builds

The local build scripts (`build-local.sh`, `os-build.sh`) look for
`buildroot/cache/rust-toolchain.tar.zst` on disk. You can populate this
manually by downloading the `rust-toolchain-cache-*` artifact from a
successful CI run.

## Updating the Cached Toolchain

When the Rust version changes in the buildroot defconfig or the uclibc patches
are updated:

1. Trigger a CI build with **"Build Rust from source"** set to `true`.
   This ignores any existing cache and rebuilds from source.
2. The new toolchain is automatically cached by `actions/cache` for future
   CI runs.
3. *(Optional, for local builds)* Download the `rust-toolchain-cache-*`
   artifact from the CI run and place it in this directory.

## Build Script Flags

| Script | Flag |
|--------|------|
| GitHub Actions | `build_rust_from_source: true` (workflow\_dispatch input) |
| `build-local.sh` | `--build-rust-from-source` |
| `os-build.sh` | `BUILD_RUST_FROM_SOURCE=1` (environment variable) |

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
