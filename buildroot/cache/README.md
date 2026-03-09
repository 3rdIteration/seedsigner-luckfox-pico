# Buildroot Rust Toolchain Cache

This directory stores a pre-built Rust cross-compilation toolchain for the
`armv7-unknown-linux-uclibceabihf` target used by all LuckFox Pico variants.

## Why?

Building Rust from source for a uclibc Tier 3 target takes **~2 hours** on
GitHub Actions runners. Since all five build variants (Mini SD, Mini NAND,
Pro\_Max SD, Pro\_Max NAND, Pi eMMC) use the **identical** Rust host toolchain,
caching the built toolchain avoids rebuilding it in every CI job.

## How It Works

The toolchain tarball (`rust-toolchain.tar.zst`, ~80–120 MB) is split into
**25 MB chunks** stored as regular Git files — no Git LFS required:

```
buildroot/cache/
├── rust-toolchain.tar.zst.part00   # 25 MB
├── rust-toolchain.tar.zst.part01   # 25 MB
├── rust-toolchain.tar.zst.part02   # 25 MB
├── ...
└── README.md
```

During a build, the scripts **reassemble** the chunks and extract:

```bash
cat buildroot/cache/rust-toolchain.tar.zst.part* > /tmp/rust-toolchain.tar.zst
tar --zstd -xf /tmp/rust-toolchain.tar.zst -C "$BUILDROOT_DIR/output"
```

Stamp files are created so buildroot skips the `host-rust`, `host-rust-bin`,
and `host-rustc` packages entirely. This saves ~2 hours per build.

If no chunks are found or `--build-rust-from-source` is set, Rust is built
from source as usual.

## Updating the Cached Toolchain

When the Rust version changes in the buildroot defconfig or the uclibc patches
are updated:

1. Trigger a CI build with **"Build Rust from source"** set to `true` (or run
   locally with `--build-rust-from-source`).
2. Download the `rust-toolchain-cache-*` artifact from the successful CI run.
3. Place the chunk files in this directory and commit:
   ```bash
   # Clear old chunks
   rm -f buildroot/cache/rust-toolchain.tar.zst.part*
   # Copy new chunks from downloaded artifact
   cp ~/Downloads/rust-toolchain-cache-*/* buildroot/cache/
   git add buildroot/cache/rust-toolchain.tar.zst.part*
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
