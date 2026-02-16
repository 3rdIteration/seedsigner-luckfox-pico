# python-numpy Package

## Overview

Custom NumPy package for LuckFox Pico buildroot, using version 1.24.3 which is compatible with GCC 8.0+.

## Why a Custom Package?

The standard buildroot python-numpy package (version 1.25.0) requires GCC >= 8.4, but the LuckFox toolchain uses GCC 8.3.0. This custom package provides NumPy 1.24.3 which only requires GCC >= 8.0.

## Version Information

- **NumPy Version**: 1.24.3
- **GCC Requirement**: >= 8.0 (compatible with LuckFox GCC 8.3.0)
- **Python**: 3.x
- **Size**: ~10-15 MB
- **BLAS/LAPACK**: Not included (uses pure Python fallbacks for simplicity)

## NumPy GCC Version Requirements

| NumPy Version | GCC Required |
|--------------|--------------|
| 1.20-1.23 | >= 7.3 |
| **1.24.3** (this package) | **>= 8.0** |
| 1.25.x | >= 8.4 |
| 1.26+ | >= 9.0 |

## Dependencies

- BR2_PACKAGE_PYTHON3
- host-python-cython (build dependency)

## Usage

This package is automatically selected when opencv-mobile Python bindings are enabled, as OpenCV requires NumPy for array operations.

### In defconfig:
```
BR2_PACKAGE_PYTHON_NUMPY=y
```

### In Python:
```python
import numpy as np
arr = np.array([1, 2, 3])
```

## Build Configuration

The package is built without BLAS/LAPACK libraries to simplify dependencies. NumPy will use pure Python fallbacks for linear algebra operations. This is sufficient for basic array operations needed by OpenCV and SeedSigner.

## Size Impact

- Library: ~5-6 MB
- Python module: ~4-5 MB
- Total: ~10-15 MB

## Compatibility

Compatible with:
- opencv-mobile Python bindings (cv2 module)
- SciPy (if needed)
- Other scientific Python libraries

## Notes

- This is a minimal configuration focusing on core NumPy functionality
- Advanced features requiring additional dependencies may not be available
- Sufficient for OpenCV image array operations and basic numerical computing
