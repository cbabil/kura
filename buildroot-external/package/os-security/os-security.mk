OS_SECURITY_VERSION = 1.0.0
OS_SECURITY_SITE = $(BR2_EXTERNAL_OS_PATH)/package/os-security/src
OS_SECURITY_SITE_METHOD = local
OS_SECURITY_LICENSE = MIT

OS_SECURITY_DEPENDENCIES = python3

# Brand from environment (exported by build.sh); default must match
# DEFAULT_BRAND in scripts/common/brand-defaults.sh
_OS_BRAND = $(or $(OS_BRAND),falken)

define OS_SECURITY_INSTALL_TARGET_CMDS
	# Install security scripts
	$(INSTALL) -D -m 0644 $(@D)/security_hardening.py \
		$(TARGET_DIR)/usr/lib/$(_OS_BRAND)/security_hardening.py

	# Install launcher (source name is static, install target is branded)
	$(INSTALL) -D -m 0755 $(@D)/os-security \
		$(TARGET_DIR)/usr/bin/$(_OS_BRAND)-security

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/os-security.service \
		$(TARGET_DIR)/usr/lib/systemd/system/$(_OS_BRAND)-security.service
endef

define OS_SECURITY_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/os-security.service \
		$(TARGET_DIR)/usr/lib/systemd/system/$(_OS_BRAND)-security.service
endef

$(eval $(generic-package))
