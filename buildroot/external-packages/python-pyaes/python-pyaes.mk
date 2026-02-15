################################################################################
#
# python-pyaes
#
################################################################################

PYTHON_PYAES_VERSION = 1.6.1
PYTHON_PYAES_SOURCE = pyaes-$(PYTHON_PYAES_VERSION).tar.gz
PYTHON_PYAES_SITE = https://files.pythonhosted.org/packages/source/p/pyaes
PYTHON_PYAES_SETUP_TYPE = setuptools
PYTHON_PYAES_LICENSE = MIT
PYTHON_PYAES_LICENSE_FILES = LICENSE.txt

$(eval $(python-package))
