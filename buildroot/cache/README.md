# Buildroot Rust Toolchain Cache

This directory stores a pre-built Rust cross-compilation toolchain for the
`armv7-unknown-linux-uclibceabihf` target used by all LuckFox Pico variants.

## Why?

Building Rust from source for a uclibc Tier 3 target takes **~2 hours** on
GitHub Actions runners. Since all five build variants (Mini SD, Mini NAND,
Pro\_Max SD, Pro\_Max NAND, Pi eMMC) use the **identical** Rust host toolchain,
caching the built toolchain avoids rebuilding it in every CI job.

## File

| File | Contents |
|------|----------|
| `rust-toolchain.tar.zst` | Pre-built `host-rust 1.82.0` output: `rustc`, `cargo`, `rust-std` for host (x86\_64) and target (armv7-uclibc), plus buildroot stamp files. Tracked by **Git LFS**. |

## How It Works

During a build, the scripts check for `buildroot/cache/rust-toolchain.tar.zst`:

- **If present** (default): The tarball is extracted into the buildroot output
  directory and stamp files are created so buildroot skips the `host-rust`,
  `host-rust-bin`, and `host-rustc` packages entirely. This saves ~2 hours.

- **If absent or `--build-rust-from-source` is set**: Rust is built from source
  as usual. After a successful build, the toolchain is packaged as a CI artifact
  that can be downloaded and committed here.

## Updating the Cached Toolchain

When the Rust version changes in the buildroot defconfig or the uclibc patches
are updated:

1. Trigger a CI build with **"Build Rust from source"** set to `true` (or run
   locally with `--build-rust-from-source`).
2. Download the `rust-toolchain-cache` artifact from the successful CI run.
3. Place `rust-toolchain.tar.zst` in this directory and commit:
   ```bash
   cp ~/Downloads/rust-toolchain.tar.zst buildroot/cache/
   git add buildroot/cache/rust-toolchain.tar.zst
   git commit -m "Update cached Rust toolchain"
   ```

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
