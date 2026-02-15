################################################################################
#
# nfc-bindings
#
################################################################################

NFC_BINDINGS_VERSION = 0.1-placeholder
NFC_BINDINGS_SITE = $(call github,3rdIteration,nfc-bindings,$(NFC_BINDINGS_VERSION))
NFC_BINDINGS_LICENSE = BSD-3
NFC_BINDINGS_LICENSE_FILES = LICENSE
NFC_BINDINGS_DEPENDENCIES = libnfc libusb libusb-compat
NFC_BINDINGS_INSTALL_STAGING = YES

NFC_BINDINGS_CONF_OPTS = \
	-DPYTHON_EXECUTABLE=$(HOST_DIR)/bin/python3 \
	-DPYTHON_INCLUDE_DIR=$(STAGING_DIR)/usr/include/python3.11 \
	-DPYTHON_LIBRARY=$(STAGING_DIR)/usr/lib/libpython3.11.so \
	-DPYTHON_VERSION=3.11

$(eval $(cmake-package))
