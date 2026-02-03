STRATURA_SECURITY_VERSION = 1.0.0
STRATURA_SECURITY_SITE = $(BR2_EXTERNAL_STRATURAOS_PATH)/package/stratura-security/src
STRATURA_SECURITY_SITE_METHOD = local
STRATURA_SECURITY_LICENSE = MIT

STRATURA_SECURITY_DEPENDENCIES = python3

define STRATURA_SECURITY_INSTALL_TARGET_CMDS
	# Install security scripts
	$(INSTALL) -D -m 0644 $(@D)/security_hardening.py \
		$(TARGET_DIR)/usr/lib/stratura/security_hardening.py

	# Install launcher
	$(INSTALL) -D -m 0755 $(@D)/stratura-security \
		$(TARGET_DIR)/usr/bin/stratura-security

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/stratura-security.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-security.service
endef

define STRATURA_SECURITY_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/stratura-security.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-security.service
endef

$(eval $(generic-package))
