# opencv-mobile Package for LuckFox Pico

This package provides a minimal build of OpenCV specifically optimized for embedded systems like the LuckFox Pico.

## About opencv-mobile

opencv-mobile is a minimal build of the OpenCV library designed for mobile and embedded platforms. It includes only essential modules (core and imgproc) without unnecessary dependencies, resulting in a much smaller footprint than full OpenCV.

- **Source**: https://github.com/nihui/opencv-mobile
- **Size**: ~5-6 MB (vs ~50 MB for full OpenCV)
- **Modules**: core, imgproc, features2d, photo, video
- **No Rust**: Pure C++ implementation, works on uclibc

## Features

- ✅ Native LuckFox support (arm-rockchip830-linux-uclibcgnueabihf)
- ✅ Works on uclibc (LuckFox's C library)
- ✅ Python 3 bindings available (cv2 module)
- ✅ Color space conversions (NV12, YUYV to RGB)
- ✅ Image processing functions
- ✅ 90% smaller than full OpenCV

## Enabling opencv-mobile

### Option 1: Edit defconfig

Uncomment the following lines in `buildroot/configs/luckfox_pico_defconfig`:

```
# BR2_PACKAGE_OPENCV_MOBILE is not set
# BR2_PACKAGE_OPENCV_MOBILE_PYTHON is not set
```

Change to:

```
BR2_PACKAGE_OPENCV_MOBILE=y
BR2_PACKAGE_OPENCV_MOBILE_PYTHON=y
```

### Option 2: Use buildroot menuconfig

```bash
cd luckfox-pico
make buildroot-menuconfig
```

Navigate to:
```
Computer Vision --->
    [*] opencv-mobile
    [*]   Python bindings
```

## Usage

### In Python (SeedSigner)

Once enabled, you can use OpenCV in Python:

```python
import cv2
import numpy as np

# Color conversion (NV12 to RGB)
rgb_frame = cv2.cvtColor(nv12_frame, cv2.COLOR_YUV2RGB_NV12)

# Or use with camera
cap = cv2.VideoCapture(0)
ret, frame = cap.read()
```

### Camera Integration

With opencv-mobile enabled, SeedSigner can use the simpler `luckfox-staging-portability` branch which relies on OpenCV for camera operations instead of custom converters.

## Size Impact

- opencv-mobile library: ~4-5 MB
- Python bindings: ~1-2 MB
- **Total increase**: ~6 MB (~4% of total image)

## Performance

- Color conversion: ~5-15ms per frame
- Still suitable for QR code scanning (4-10 fps)
- Slower than custom C converter (~1ms) but acceptable

## When to Use

**Enable opencv-mobile if you want**:
- Standard OpenCV API
- Cross-platform compatible code
- Simpler camera implementation
- Future flexibility for image processing

**Keep disabled (default) if you want**:
- Minimal size
- Fastest performance
- Custom optimized converters

## Compatibility

- ✅ LuckFox Pico Mini (RV1103)
- ✅ LuckFox Pico Pro Max (RV1106)
- ✅ uclibc toolchain
- ✅ Buildroot 2024.11.x
- ✅ Python 3.12

## Dependencies

Automatically handled by buildroot:
- host-cmake
- host-pkgconf
- zlib
- python3 (if Python bindings enabled)
- python-numpy (if Python bindings enabled)

## Build Time

Adding opencv-mobile increases build time by approximately:
- ~10-15 minutes for library
- ~5 minutes for Python bindings

## Alternative: Custom NV12 Converter

By default (opencv-mobile disabled), SeedSigner uses a custom C binary for NV12 conversion:
- Size: 13 KB
- Speed: ~1ms per frame
- LuckFox-specific

This is optimal for production builds focused on minimal size and maximum performance.

## Technical Details

### CMake Options

The package uses opencv-mobile's minimal configuration:
- Disabled: DNN, ML, objdetect, videoio, imgcodecs
- Enabled: core, imgproc, features2d, photo, video
- OpenMP: enabled for parallelization
- Static libraries with shared Python module

### Toolchain

Uses LuckFox SDK's native toolchain:
- Compiler: arm-rockchip830-linux-uclibcgnueabihf-gcc
- Architecture: ARMv7-a
- Float ABI: hard
- FPU: NEON

## Troubleshooting

### Build fails with CMake error

Ensure buildroot has host-cmake installed (automatically handled as dependency).

### Python module not found

Verify Python bindings are enabled:
```bash
grep BR2_PACKAGE_OPENCV_MOBILE_PYTHON .config
```

Should show:
```
BR2_PACKAGE_OPENCV_MOBILE_PYTHON=y
```

### Import cv2 fails at runtime

Check that opencv-mobile was actually built:
```bash
find output/target -name "cv2*.so"
```

Should show the cv2 Python module in site-packages.

## See Also

- [opencv-mobile repository](https://github.com/nihui/opencv-mobile)
- [opencv-mobile documentation](https://github.com/nihui/opencv-mobile/blob/master/README.md)
- [OpenCV documentation](https://docs.opencv.org/)

## License

opencv-mobile is licensed under Apache License 2.0, same as OpenCV.
