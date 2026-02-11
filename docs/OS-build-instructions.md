# OS Build Instructions

This project supports two build workflows:

1. **Docker (default/recommended)** for reproducible builds and minimal host setup.
2. **Local host build (development option)** for faster iteration and debugging.

---

## Option 1: Docker Build (Default)

Run these commands from `buildroot/`.

### Build the builder image

```bash
cd buildroot/
docker build -t foxbuilder:latest .
```

### Ensure host repositories exist

These directories are expected under `$HOME`:

```bash
ls ~
luckfox-pico  seedsigner  seedsigner-luckfox-pico  seedsigner-os
```

Clone them if missing:

```bash
# Luckfox SDK
git clone https://github.com/lightningspore/luckfox-pico.git \
    --depth=1 --single-branch

# SeedSigner OS packages
git clone https://github.com/seedsigner/seedsigner-os.git \
    --depth=1 --single-branch

# SeedSigner application code
git clone https://github.com/lightningspore/seedsigner.git \
    --depth=1 -b luckfox-dev --single-branch
```

### Launch container

```bash
LUCKFOX_SDK_DIR=$HOME/luckfox-pico
SEEDSIGNER_CODE_DIR=$HOME/seedsigner
LUCKFOX_BOARD_CFG_DIR=$HOME/seedsigner-luckfox-pico
SEEDSIGNER_OS_DIR=$HOME/seedsigner-os

docker run -d --name luckfox-builder \
    -v $LUCKFOX_SDK_DIR:/mnt/host \
    -v $SEEDSIGNER_CODE_DIR:/mnt/ss \
    -v $LUCKFOX_BOARD_CFG_DIR:/mnt/cfg \
    -v $SEEDSIGNER_OS_DIR:/mnt/ssos \
    foxbuilder:latest
```

Enter container:

```bash
docker exec -it luckfox-builder bash
```

Start build:

```bash
/mnt/cfg/buildroot/add_package_buildroot.sh
```

---

## Option 2: Local Host Build (Development)

Use this when iterating locally without Docker.

### Host requirements

- Ubuntu/Debian-like Linux host (recommended)
- `git`, `bash`, `make`, `gcc`, `g++`, `python3`, `rsync`, `cpio`, `bc`, `file`
- 20GB+ free disk space recommended

Install common dependencies:

```bash
sudo apt update
sudo apt install -y git build-essential python3 rsync cpio bc file
```

### Run local build

```bash
cd buildroot
./os-build.sh auto
```

Useful variants:

```bash
# Build one model only
BUILD_MODEL=mini ./os-build.sh auto
BUILD_MODEL=max ./os-build.sh auto

# Lower resource usage
BUILD_JOBS=2 ./os-build.sh auto

# Include NAND packaging
./os-build.sh auto-nand
```

---

## Build Configuration + Package Selection (Common)

After entering the SDK environment (container shell or local build flow), configure targets/packages as needed:

```bash
# Choose target board/profile
./build.sh lunch

# Configure buildroot package selection
./build.sh buildrootconfig
```

Select Pico Pro Max / buildroot / SPI, and save.

Saved config path:

```bash
sysdrv/source/buildroot/buildroot-2023.02.6/.config
```

Sanity checks:

```bash
grep "LIBCAMERA" sysdrv/source/buildroot/buildroot-2023.02.6/.config
grep "ZBAR" sysdrv/source/buildroot/buildroot-2023.02.6/.config
grep "LIBJPEG" sysdrv/source/buildroot/buildroot-2023.02.6/.config
```

List all enabled packages:

```bash
grep -v "^#" sysdrv/source/buildroot/buildroot-2023.02.6/.config
```

Build steps:

```bash
./build.sh uboot
./build.sh kernel
./build.sh rootfs
./build.sh media
```

Package:

```bash
./build.sh firmware
```

---

## Output + Flashing

Expected image outputs (path varies by workflow):

- Docker SDK mount path: `/mnt/host/output/image/`
- Local workflow path: `buildroot/output/image/`

Create single flashable image (when needed):

```bash
cd output/image
../../blkenvflash seedsigner-luckfox-pico.img
```

Flash to SD card:

```bash
sudo dd bs=4M \
    status=progress \
    if=seedsigner-luckfox-pico.img \
    of=/dev/diskX
```

Replace `/dev/diskX` with the correct SD card device.

---

## Official resources

[Luckfox Pico Official Flashing Guide](https://wiki.luckfox.com/Luckfox-Pico/Linux-MacOS-Burn-Image/) - Official documentation for flashing images to the Luckfox Pico device on Linux and macOS systems
