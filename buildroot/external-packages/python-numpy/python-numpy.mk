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
PYTHON_NUMPY_DEPENDENCIES = clapack host-python-cython

# Custom version 1.24.3 for GCC 8.0+ compatibility
# Standard buildroot uses 1.25.0 which requires GCC >= 8.4
# LuckFox toolchain has GCC 8.3.0

define PYTHON_NUMPY_CONFIGURE_CMDS
	-$(RM) -rf $(@D)/site.cfg
	echo "[DEFAULT]" >> $(@D)/site.cfg
	echo "library_dirs = $(STAGING_DIR)/usr/lib" >> $(@D)/site.cfg
	echo "include_dirs = $(STAGING_DIR)/usr/include" >> $(@D)/site.cfg
	echo "" >> $(@D)/site.cfg
	echo "[blas_opt]" >> $(@D)/site.cfg
	echo "libraries = blas, cblas, atlas" >> $(@D)/site.cfg
	echo "" >> $(@D)/site.cfg
	echo "[lapack_opt]" >> $(@D)/site.cfg
	echo "libraries = lapack, f77blas, cblas, atlas" >> $(@D)/site.cfg
endef

# Use the setuptools infrastructure
$(eval $(python-package))
