# SeedSigner Build System

Docker-based build is the default/recommended workflow for reproducible OS images and minimal host pollution.

## Default: Docker Build

### Requirements

- Docker (any recent version)
- 4GB+ RAM recommended
- 3GB+ free disk space
- Linux, macOS, or Windows with WSL2

### Quick Start

```bash
./build.sh build
# Artifacts automatically available in ./build-output/
```

### Docker Commands

| Command | Description |
|---------|-------------|
| `./build.sh build` | Full automated build (artifacts auto-exported) |
| `./build.sh build --jobs N` | Build with N parallel jobs |
| `./build.sh interactive` | Interactive debugging mode |
| `./build.sh shell` | Direct shell access |
| `./build.sh clean` | Clean containers and volumes |
| `./build.sh status` | Show system status |

## Local Host Build (Development Option)

Use local builds when you want faster iteration/debugging and are okay with host dependencies:

```bash
./os-build.sh auto
```

Useful options:

```bash
# Build one model only
BUILD_MODEL=mini ./os-build.sh auto
BUILD_MODEL=max ./os-build.sh auto

# Tune parallel jobs
BUILD_JOBS=4 ./os-build.sh auto

# Include NAND artifacts
./os-build.sh auto-nand
```

Local build output artifacts are written under:

```bash
./output/image/
```

## Notes

- Docker workflow remains the best default for release/reproducible images.
- Local workflow is primarily intended for active development and troubleshooting.
