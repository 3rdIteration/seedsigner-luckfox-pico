################################################################################
#
# python-shamir-mnemonic
#
################################################################################

PYTHON_SHAMIR_MNEMONIC_VERSION = 0.3.0
PYTHON_SHAMIR_MNEMONIC_SOURCE = shamir-mnemonic-$(PYTHON_SHAMIR_MNEMONIC_VERSION).tar.gz
PYTHON_SHAMIR_MNEMONIC_SITE = https://files.pythonhosted.org/packages/source/s/shamir-mnemonic
PYTHON_SHAMIR_MNEMONIC_SETUP_TYPE = setuptools
PYTHON_SHAMIR_MNEMONIC_LICENSE = MIT
PYTHON_SHAMIR_MNEMONIC_LICENSE_FILES = LICENSE

$(eval $(python-package))
