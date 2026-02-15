################################################################################
#
# openct
#
################################################################################

OPENCT_VERSION = 0.6.21
OPENCT_SITE = $(call github,3rdIteration,openct,$(OPENCT_VERSION))
OPENCT_LICENSE = LGPL-2.1
OPENCT_LICENSE_FILES = COPYING
OPENCT_DEPENDENCIES = pcsc-lite
OPENCT_INSTALL_STAGING = YES
OPENCT_CONF_OPTS =
OPENCT_AUTORECONF = YES

$(eval $(autotools-package))
