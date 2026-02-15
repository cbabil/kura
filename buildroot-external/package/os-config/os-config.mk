OS_CONFIG_VERSION = 1.0.0
OS_CONFIG_SITE = $(BR2_EXTERNAL_OS_PATH)/package/os-config/src
OS_CONFIG_SITE_METHOD = local
OS_CONFIG_LICENSE = MIT

OS_CONFIG_DEPENDENCIES = python3 network-manager

# Brand from environment (exported by build.sh); default must match
# DEFAULT_BRAND in scripts/common/brand-defaults.sh
_OS_BRAND = $(or $(OS_BRAND),falken)

define OS_CONFIG_INSTALL_TARGET_CMDS
	# Install config manager (source name is static, install target is branded)
	$(INSTALL) -D -m 0755 $(@D)/os-config \
		$(TARGET_DIR)/usr/bin/$(_OS_BRAND)-config

	# Install network manager module
	$(INSTALL) -D -m 0644 $(@D)/network_manager.py \
		$(TARGET_DIR)/usr/lib/$(_OS_BRAND)/network_manager.py

	# Install default configuration
	$(INSTALL) -d $(TARGET_DIR)/etc/$(_OS_BRAND)
	$(INSTALL) -D -m 0644 $(@D)/config.json \
		$(TARGET_DIR)/etc/$(_OS_BRAND)/config.json

	# Install NetworkManager config
	$(INSTALL) -d $(TARGET_DIR)/etc/NetworkManager/conf.d
	$(INSTALL) -D -m 0644 $(@D)/00-os-network.conf \
		$(TARGET_DIR)/etc/NetworkManager/conf.d/00-$(_OS_BRAND)-network.conf

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/os-config.service \
		$(TARGET_DIR)/usr/lib/systemd/system/$(_OS_BRAND)-config.service
endef

define OS_CONFIG_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/os-config.service \
		$(TARGET_DIR)/usr/lib/systemd/system/$(_OS_BRAND)-config.service
endef

$(eval $(generic-package))
