# Smartcard and NFC Integration

This document describes the smartcard and NFC support packages integrated into the SeedSigner LuckFox Pico build.

## Overview

The build now includes comprehensive smartcard and NFC support through six additional packages:

1. **ccid-sec1210** - CCID driver with serial reader support
2. **python-pyscard** - Python bindings for PC/SC
3. **python-pysatochip** - Python API for Satochip devices
4. **openct** - Smartcard terminal middleware
5. **ifdnfc** - NFC reader support for PC/SC
6. **nfc-bindings** - Python NFC bindings

## Package Details

### ccid-sec1210

**Purpose**: Provides CCID (Chip Card Interface Device) drivers for both USB and serial smartcard readers.

**Key Features**:
- USB CCID support via `libccid.so`
- Serial CCID support via `libccidtwin.so` (for SEC1210 reader)
- Configured with `-Dserial=true` to enable serial support

**Installation Paths**:
```
/usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Linux/libccid.so
/usr/lib/pcsc/drivers/serial/libccidtwin.so
/etc/reader.conf.d/libccidtwin
```

**Configuration**: See `buildroot/rootfs-overlay/etc/reader.conf.d/sec1210`

### python-pyscard

**Purpose**: Python wrapper for PC/SC lite, enabling Python applications to communicate with smartcards.

**Version**: 2.3.1  
**Source**: https://github.com/LudovicRousseau/pyscard  
**Dependencies**: pcsc-lite, host-swig  

**Usage Example**:
```python
from smartcard.System import readers
r = readers()
connection = r[0].createConnection()
connection.connect()
```

### python-pysatochip

**Purpose**: Python API for Satochip hardware wallets and related devices.

**Version**: 0.5-alpha  
**Source**: https://github.com/3rdIteration/pysatochip  
**Supports**: Seedkeeper, Satochip, Satodime  

**Usage Example**:
```python
import pysatochip
# API for Satochip device interaction
```

### openct

**Purpose**: OpenCT smartcard terminal middleware library providing drivers for various smartcard readers and tokens.

**Source**: https://github.com/3rdIteration/openct

### ifdnfc

**Purpose**: PC/SC IFD Handler implementation for NFC-based smartcard readers.

**Source**: https://github.com/3rdIteration/ifdnfc  
**Dependencies**: pcsc-lite, libnfc  

### nfc-bindings

**Purpose**: Python bindings for libnfc (Near Field Communication library).

**Source**: https://github.com/3rdIteration/nfc-bindings  
**Dependencies**: libnfc, libusb, libusb-compat  

## System Configuration

### PC/SC Daemon (pcscd)

The PC/SC daemon is automatically started at boot through init scripts:

**Init Scripts**:
- `/etc/init.d/S00smartcard` - Early smartcard initialization
- `/etc/init.d/S01pcscd` - PC/SC daemon startup

**Configuration**:
- `/etc/reader.conf.d/` - Reader configurations
  - `sec1210` - SEC1210 serial reader
  - `libifdnfc` - NFC reader

### SEC1210 Serial Reader

The SEC1210 is a serial smartcard reader connected via UART.

**Configuration** (`/etc/reader.conf.d/sec1210`):
```
DEVICENAME        /dev/ttyAMA0:SEC1210URT
FRIENDLYNAME      "SEC1210"
LIBPATH           /usr/lib/pcsc/drivers/serial/libccidtwin.so
```

**UART Device**: `/dev/ttyAMA0`  
**Driver**: `libccidtwin.so`

### NFC Configuration

**libnfc Configuration**: `/etc/nfc/libnfc.conf`

Supports NFC-based smartcard operations including:
- ISO14443A/B card reading
- PN532 I2C interface support
- Smartcard emulation

### GnuPG Smartcard Support

**Configuration**: `/root/.gnupg/scdaemon.conf`

Enables GPG operations with smartcards including:
- Key generation on card
- Signing operations
- Authentication
- Decryption

## Build Integration

These packages are integrated into the buildroot build process through the GitHub Actions workflow:

### Workflow Steps

1. **Install SeedSigner packages** step copies external packages:
   ```bash
   cp -rv ../seedsigner-luckfox-pico/buildroot/external-packages/* "$PACKAGE_DIR/"
   ```

2. **Config.in Menu** is updated with:
   ```
   menu "Smartcard and NFC Support"
       source "package/ccid-sec1210/Config.in"
       source "package/openct/Config.in"
       source "package/ifdnfc/Config.in"
       source "package/nfc-bindings/Config.in"
       source "package/python-pyscard/Config.in"
       source "package/python-pysatochip/Config.in"
   endmenu
   ```

3. **Buildroot configuration** enables all packages via `buildroot/configs/luckfox_pico_defconfig`:
   ```
   BR2_PACKAGE_CCID_SEC1210=y
   BR2_PACKAGE_OPENCT=y
   BR2_PACKAGE_IFDNFC=y
   BR2_PACKAGE_NFC_BINDINGS=y
   BR2_PACKAGE_PYTHON_PYSCARD=y
   BR2_PACKAGE_PYTHON_PYSATOCHIP=y
   ```

## Testing

### Verify Package Installation

**Check Libraries**:
```bash
# USB CCID driver
ls -la /usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Linux/libccid.so

# Serial CCID driver
ls -la /usr/lib/pcsc/drivers/serial/libccidtwin.so
```

**Check Python Modules**:
```bash
# pyscard
python3 -c "import smartcard; print(smartcard.__version__)"

# pysatochip
python3 -c "import pysatochip; print('pysatochip loaded')"
```

### Test PC/SC Functionality

**List Readers**:
```bash
pcsc_scan
```

**Python Test**:
```python
from smartcard.System import readers

# List all readers
r = readers()
print("Available readers:", r)

# Connect to first reader
if r:
    connection = r[0].createConnection()
    connection.connect()
    print("Connected to reader:", r[0])
```

### Test NFC Functionality

**List NFC Devices**:
```bash
nfc-list
```

**Scan for NFC Tags**:
```bash
nfc-scan-device
```

## Troubleshooting

### PC/SC Daemon Issues

**Check daemon status**:
```bash
ps aux | grep pcscd
```

**Restart daemon**:
```bash
/etc/init.d/S01pcscd restart
```

**View logs**:
```bash
pcscd --foreground --debug
```

### Reader Not Detected

**Check reader configuration**:
```bash
cat /etc/reader.conf.d/sec1210
```

**Verify serial port**:
```bash
ls -la /dev/ttyAMA0
```

**Test serial connection**:
```bash
echo "test" > /dev/ttyAMA0
```

### Python Import Errors

**Check module installation**:
```bash
python3 -c "import sys; print(sys.path)"
ls -la /usr/lib/python3.*/site-packages/
```

**Reinstall package** (if needed):
```bash
cd /path/to/buildroot
make python-pyscard-rebuild
```

## References

- **CCID Driver**: https://github.com/LudovicRousseau/CCID
- **pyscard**: https://github.com/LudovicRousseau/pyscard
- **PC/SC Lite**: https://pcsclite.apdu.fr/
- **libnfc**: https://github.com/nfc-tools/libnfc
- **Buildroot**: https://buildroot.org/

## License

All packages maintain their original licenses:
- ccid-sec1210: LGPL-2.1+
- python-pyscard: LGPL
- python-pysatochip: LGPL
- Other packages: See individual package licenses
