# Buildroot Rust Toolchain Cache

This directory caches the pre-built Rust cross-compilation toolchain for the
`armv7-unknown-linux-uclibceabihf` target used by all LuckFox Pico variants.

## Why?

Building Rust from source for a uclibc Tier 3 target takes **~2 hours**.
Caching the built toolchain avoids rebuilding it every time.

## Caching Strategy

Each build method uses a different caching approach:

| Build Method | Caching | Details |
|---|---|---|
| **GitHub Actions** (`build.yml`) | `actions/cache` | Automatic; keyed on defconfig hash |
| **Local** (`build-local.sh`) | Local file | `buildroot/cache/rust-toolchain.tar.zst` |
| **Docker** (`os-build.sh`) | None | Always builds from source |

### GitHub Actions (CI)

Uses `actions/cache@v4` to cache `/tmp/rust-toolchain.tar.zst`. The cache key
is derived from the defconfig file hash, so a new toolchain is automatically
built when the Rust version or target configuration changes.

To force a rebuild: trigger a workflow\_dispatch with `build_rust_from_source: true`.

### Local Builds

After the first build, the toolchain is saved to
`buildroot/cache/rust-toolchain.tar.zst` (~80–120 MB, git-ignored).
Subsequent builds automatically restore from this file, saving ~2 hours.

To force a rebuild: pass `--build-rust-from-source`:
```bash
./buildroot/build-local.sh --build-rust-from-source
```

### Docker Builds

Docker containers are ephemeral, so no caching is used. Rust is always built
from source inside the container.

## How the Cache Works

The tarball contains:
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

On restore, the tarball is extracted into the buildroot output directory and
stamp files are created so buildroot skips the `host-rust`, `host-rust-bin`,
and `host-rustc` packages entirely.
