################################################################################
#
# python-pgpy
#
################################################################################

PYTHON_PGPY_VERSION = 0.6.0
PYTHON_PGPY_SOURCE = PGPy-$(PYTHON_PGPY_VERSION).tar.gz
PYTHON_PGPY_SITE = https://files.pythonhosted.org/packages/source/P/PGPy
PYTHON_PGPY_SETUP_TYPE = setuptools
PYTHON_PGPY_LICENSE = BSD-3-Clause
PYTHON_PGPY_LICENSE_FILES = LICENSE
PYTHON_PGPY_DEPENDENCIES = host-python-setuptools

$(eval $(python-package))
