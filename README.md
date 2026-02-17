# seedsigner-luckfox-pico
Port of the SeedSigner code to support the LuckFox Pico Linux board family. Since this device is still an embedded Linux device, like the Raspberry Pi, the changes are fairly minimal in order to access the buttons and the camera. This repo mostly pertains to the Buildroot OS build instructions, the KiCAD schematic and PCB design files, and 3D models of cases for the assembled device.

SeedSigner code fork: https://github.com/3rdIteration/seedsigner/tree/luckfox-staging-portability


## Hardware Photos
_Most Recent Iteration: LuckFox Pico Mini B with no onboard SPI flash_
![LuckFox Pico Mini - SeedSigner](img/slp-2.webp)
![LuckFox Pico Mini - SeedSigner 2](img/slp-1.webp)


_Previous Iteration: LuckFox Pico Pro Max (More Flash, SPI Flash)_
![LuckFox Pico Pro Max - SeedSigner](img/luckfox-devboard-front.webp)
![Case From Behind](img/luckfox-devboard-back.webp)

## Demo Videos

### First Look: SeedSigner running on LuckFox Pico Linux devboard
[![SeedSigner on LuckFox Pico Pro Max](https://img.youtube.com/vi/WHkOSn-lPG4/0.jpg)](https://www.youtube.com/watch?v=WHkOSn-lPG4)


## Materials Needed
Check out the shopping list for a parts list of various LuckFox-based hardware configurations: [here](docs/shopping_list.md)

These example builds can build a device for around $60.


## OS Image Build with Buildroot

### Build with GitHub Actions (Recommended for Most Users)
The easiest way to build the SeedSigner OS image is using GitHub Actions. This method builds directly on GitHub's infrastructure without requiring Docker:

1. Fork this repository to your GitHub account
2. Navigate to the "Actions" tab in your fork
3. Select the "Build SeedSigner OS" workflow
4. The workflow runs automatically on pushes to `main`, `develop`, or `master` branches
5. Builds are created for both LuckFox Pico Mini (RV1103) and Pro Max (RV1106) hardware
6. Wait for the build to complete (typically 60-120 minutes)
7. Download the artifacts from the workflow run

The GitHub Actions workflow:
- Installs all required dependencies on Ubuntu 22.04
- Clones the LuckFox Pico SDK (customized fork), SeedSigner code, and SeedSigner OS packages
- Configures buildroot with SeedSigner-specific packages
- Builds the complete OS image
- Creates flashable SD card images and NAND flash bundles for SD_CARD and SPI_NAND boot media
- Provides detailed build summaries and flashing instructions

### Build Locally with Docker (Simple Method)
For users who want to build locally, a simple build script is available:

```bash
cd buildroot/
./build.sh build --microsd
```

Build artifacts will be automatically available in `buildroot/build-output/`. The script handles Docker image building, repository caching, and artifact export automatically.

**Additional options:**
- `--nand` - Build NAND flash bundles
- `--model mini` or `--model max` - Build specific hardware only
- `--jobs N` - Use N parallel jobs
- See `./build.sh --help` for all options

### Build Locally Without Docker (Advanced Users)
For development or if you prefer not to use Docker, an automated local build script is available (Ubuntu 22.04):

```bash
cd buildroot/
./build-local.sh --check-deps  # Install dependencies (first time)
./build-local.sh               # Build for Mini with SD card
```

**Additional options:**
- `--hardware mini|max` - Choose hardware type
- `--boot sd|nand` - Choose boot medium
- See `./build-local.sh --help` for all options

For more details and manual step-by-step instructions, see [OS-build-instructions.md](docs/OS-build-instructions.md).

![Buildroot Prompt](img/seedsigner-buildroot-setup.webp)

## Dev Machine Setup

### Install ADB
Developing for the LuckFox Pico device is quite convenient since the devices never connect to the internet and you can access the device shell using `adb`. You can push files back and forth to your dev machine, and you can access the device as a shell easily.
```
# mac
brew install homebrew/cask/android-platform-tools

# linux
sudo apt install android-tools-adb
```

### ADB Connection and Device Management

1. Connect to the device:
```
# List connected devices
adb devices

# Connect to device shell
adb shell
```

2. File Operations:
```
# Push files to device
adb push local_file.txt /remote/path/

# Sync the code repo for local development
adb push /repos/seedsigner/src /seedsigner

# Pull files from device
adb pull /seedsigner/config.json .

# List files on device
adb shell ls /path/to/directory
```

## Hardware Identification
Notice the left device has an empty PCB footprint pattern on it. This is where the optional SPI flash is soldered on. For the SeedSigner project we don't want permanent storage, so avoid devices with soldered SPI flash.

```
LEFT:  LuckFox Pico Mini A -> No Flash
RIGHT: LuckFox Pico Mini B -> Soldered Flash
```
![LuckFox Pico Mini](img/luckfox-pico-mini-storage.webp)


## Flashing the Device

### Flash MicroSD Card
```
sudo dd bs=4M status=progress if=seedsigner-luckfox-pico-YYYYmmdd_hhmmss.img of=/dev/diskX
```
Replace `/dev/diskX` with your actual SD card device path.


## LuckFox Pico OS Modifications
We have forked the [LuckFox Pico SDK](https://github.com/3rdIteration/luckfox-pico) in order to enable various hardware features like pull-up resistors, adjust video RAM, and other things.

### Camera Memory
The LuckFox devotes some of its memory for camera-related algorithms, but we don't use this feature. Particularly on the LuckFox Pico Mini device, which only has 64MB of RAM, it is beneficial for us to reclaim a bit of this memory.

**Note:** The GitHub Actions workflow automatically sets the CMA (Contiguous Memory Allocator) size to 1M for Mini builds, freeing up approximately 20MB of RAM. This is configured by modifying `RK_BOOTARGS_CMA_SIZE` in the board configuration file.

Memory usage WITHOUT modification:
```bash
[root@luckfox ]# free -h
              total        used        free      shared  buff/cache   available
Mem:          33.0M       24.3M        1.4M      476.0K        7.3M        5.4M
Swap:             0           0           0
```

Memory usage WITH modification:
```bash
[root@luckfox ]# free -h
              total        used        free      shared  buff/cache   available
Mem:          53.0M       23.6M        1.9M      472.0K       27.5M       25.3M
Swap:             0           0           0
```

### Pull-up Resistors
Our current dev board has external pull-up resistors, since we didn't know how to enable these at the time, and it is always smart to plan ahead when designing PCBs. NOTE: Even with this commit and this change, the internal pull-ups don't seem to work.

### SPI Buffer Size
While it is possible to send SPI data in chunks, you can increase the SPI buffer size to slightly increase throughput, which is useful for larger displays.

### PWM Output
In order to control the LCD screen backlight and support true dimming of the display (instead of just changing the background color of the QR code, for example), we had to enable a PWM on a specific output pin.

## Support the Developer
If you find this project helpful and would like to support its development, you can buy me a coffee! Your support helps keep this project going and funds future improvements. Help decentralize Bitcoin hardware!

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/lightningspore)