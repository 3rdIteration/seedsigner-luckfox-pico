################################################################################
#
# python-numpy
#
################################################################################

PYTHON_NUMPY_VERSION = 1.24.3
PYTHON_NUMPY_SOURCE = numpy-$(PYTHON_NUMPY_VERSION).tar.gz
PYTHON_NUMPY_SITE = https://files.pythonhosted.org/packages/source/n/numpy
PYTHON_NUMPY_LICENSE = BSD-3-Clause
PYTHON_NUMPY_LICENSE_FILES = LICENSE.txt
PYTHON_NUMPY_SETUP_TYPE = setuptools
PYTHON_NUMPY_DEPENDENCIES = host-python-cython

# Custom version 1.24.3 for GCC 8.0+ compatibility
# Standard buildroot uses 1.25.0 which requires GCC >= 8.4
# LuckFox toolchain has GCC 8.3.0
# Built without BLAS/LAPACK for simplicity

# Use the setuptools infrastructure
$(eval $(python-package))
