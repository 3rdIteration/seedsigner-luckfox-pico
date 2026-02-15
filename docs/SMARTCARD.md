# SeedSigner Smartcard Support for LuckFox Pico

This document describes the smartcard functionality added to the SeedSigner LuckFox Pico build, based on the smartcard features from the [3rdIteration/seedsigner-os](https://github.com/3rdIteration/seedsigner-os) project.

## Overview

The smartcard support enables SeedSigner running on LuckFox Pico to interact with hardware security devices like Satochip, Seedkeeper, and other PC/SC-compatible smartcards. This functionality allows for:

- Hardware-backed seed storage on smartcards
- Secure transaction signing using smartcard-stored keys
- NFC/contactless smartcard operations
- USB and serial smartcard reader support
- Integration with GnuPG for cryptographic operations

## Supported Hardware

### Smartcard Readers

1. **USB CCID Readers** - Any PC/SC-compatible USB smartcard reader
2. **SEC1210 Serial Reader** - Dual-slot reader via serial port (`/dev/ttyAMA0`)
3. **NFC/PN532 Reader** - Contactless NFC reader via I2C (`/dev/i2c-1`)

### Smartcards

- **Satochip** - Bitcoin hardware wallet on a smartcard
- **Seedkeeper** - Secure seed backup on smartcard
- **Satodime** - Bearer bond smartcard
- **Standard PC/SC smartcards** - Any ISO 7816-compatible card

## Software Components

### Core PCSC Infrastructure

- **pcsc-lite** - PC/SC daemon for smartcard reader management
- **CCID driver** - Generic USB smartcard reader support
- **CCID SEC1210** - Serial smartcard reader driver

### NFC Support

- **libnfc** - Near Field Communication library
- **PN532 I2C** - NFC chip support via I2C
- **ifdnfc** - PC/SC IFD Handler for NFC readers
- **nfc-bindings** - Python bindings for libnfc

### Python Libraries

- **pyscard** - Python smartcard library (PC/SC wrapper)
- **pysatochip** - Python API for Satochip, Seedkeeper, and Satodime devices

### Supporting Tools

- **OpenCT** - Alternative smartcard middleware
- **GnuPG2** - GNU Privacy Guard with smartcard support
- **Pinentry (ncurses)** - PIN entry interface
- **RNG Tools** - Random number generation utilities

## Build Configuration

### Buildroot Packages Added

The following packages have been added to the buildroot configuration (`buildroot/configs/luckfox_pico_defconfig`):

```
BR2_PACKAGE_PCSC_LITE=y
BR2_PACKAGE_CCID=y
BR2_PACKAGE_CCID_SEC1210=y
BR2_PACKAGE_OPENCT=y
BR2_PACKAGE_IFDNFC=y
BR2_PACKAGE_LIBNFC=y
BR2_PACKAGE_LIBNFC_PN532_I2C=y
BR2_PACKAGE_NFC_BINDINGS=y
BR2_PACKAGE_PYTHON_PYSCARD=y
BR2_PACKAGE_PYTHON_PYSATOCHIP=y
BR2_PACKAGE_GNUPG2=y
BR2_PACKAGE_PINENTRY=y
BR2_PACKAGE_PINENTRY_NCURSES=y
BR2_PACKAGE_RNG_TOOLS=y
BR2_PACKAGE_LIBUSB=y
BR2_PACKAGE_LIBUSB_COMPAT=y
BR2_PACKAGE_HOST_PKGCONF=y
BR2_PACKAGE_HOST_SWIG=y
```

### External Package Definitions

Custom buildroot packages have been created in `buildroot/external-packages/`:

- `python-pysatochip/` - Satochip Python API
- `python-pyscard/` - pyscard library with SWIG support
- `ifdnfc/` - IFD-NFC handler
- `ccid-sec1210/` - SEC1210 serial reader support
- `nfc-bindings/` - Python NFC bindings
- `openct/` - OpenCT middleware

## Runtime Configuration

### Init Scripts

Two initialization scripts are installed to `/etc/init.d/`:

1. **S00smartcard** - Activates/deactivates IFD-NFC interface on boot
2. **S01pcscd** - Starts the PC/SC daemon for smartcard reader communication

### Reader Configuration

PCSC reader configurations in `/etc/reader.conf.d/`:

- **libifdnfc** - IFD-NFC reader configuration
- **sec1210** - SEC1210 dual-slot serial reader configuration

### NFC Configuration

NFC library configuration in `/etc/nfc/libnfc.conf`:
- Device: IFD-NFC
- Connection: `pn532_i2c:/dev/i2c-1`

### GnuPG Configuration

GnuPG smartcard daemon configuration in `/root/.gnupg/scdaemon.conf`:
- Disables built-in CCID to use PCSC-lite instead

## Hardware Setup

### I2C NFC Reader (PN532)

Connect PN532 NFC module to LuckFox Pico I2C bus:
- **VCC** → 3.3V
- **GND** → GND
- **SDA** → I2C SDA (typically GPIO pins)
- **SCL** → I2C SCL (typically GPIO pins)

Ensure I2C is enabled in the device tree and `/dev/i2c-1` exists.

### Serial Reader (SEC1210)

Connect SEC1210 reader to UART:
- Device: `/dev/ttyAMA0`
- Configured automatically by PCSC daemon

### USB Readers

USB smartcard readers are detected automatically via CCID driver when connected.

## Usage

### Starting PCSC Daemon

The PCSC daemon starts automatically on boot via the S01pcscd init script. Manual control:

```bash
# Start
/etc/init.d/S01pcscd start

# Stop
/etc/init.d/S01pcscd stop

# Restart
/etc/init.d/S01pcscd restart

# Reload (hotplug)
/etc/init.d/S01pcscd reload
```

### Checking Reader Status

```bash
# List connected readers
pcsc_scan
```

### Python Usage

```python
from smartcard.System import readers

# List readers
r = readers()
print(r)

# Connect to a card
from smartcard.util import toHexString
connection = r[0].createConnection()
connection.connect()

# Send APDU
data, sw1, sw2 = connection.transmit([0x00, 0xA4, 0x04, 0x00])
```

### Satochip/Seedkeeper Operations

Using pysatochip library:

```python
from pysatochip.CardConnector import CardConnector

# Connect to Satochip
cc = CardConnector()
cc.card_select()

# Perform operations
# (See pysatochip documentation for details)
```

## Troubleshooting

### PCSC Daemon Not Starting

Check if the daemon is running:
```bash
ps | grep pcscd
```

Check logs:
```bash
tail -f /tmp/startup.log
```

### No Readers Detected

1. Verify hardware connections
2. Check device nodes exist:
   ```bash
   ls -l /dev/ttyAMA0  # For serial reader
   ls -l /dev/i2c-1    # For NFC reader
   ```
3. Check kernel modules loaded
4. Try reloading PCSC daemon:
   ```bash
   /etc/init.d/S01pcscd reload
   ```

### NFC Reader Not Working

1. Verify I2C is enabled in device tree
2. Check I2C device detection:
   ```bash
   i2cdetect -y 1
   ```
3. Check libnfc configuration:
   ```bash
   cat /etc/nfc/libnfc.conf
   ```

## Building with Smartcard Support

The smartcard support is included by default in the LuckFox Pico SeedSigner build. The build system automatically:

1. Copies external smartcard packages to buildroot
2. Applies rootfs overlay with init scripts and configurations
3. Enables all smartcard-related packages in the defconfig

Build as normal:
```bash
cd buildroot/
./build.sh build --microsd
```

## References

- [3rdIteration/seedsigner-os](https://github.com/3rdIteration/seedsigner-os) - Original smartcard implementation
- [3rdIteration/seedsigner](https://github.com/3rdIteration/seedsigner) - SeedSigner with smartcard support
- [3rdIteration/pysatochip](https://github.com/3rdIteration/pysatochip) - Satochip Python API
- [PCSC-Lite](https://pcsclite.apdu.fr/) - PC/SC middleware
- [libnfc](https://github.com/nfc-tools/libnfc) - NFC library
