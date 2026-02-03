STRATURA_CONFIG_VERSION = 1.0.0
STRATURA_CONFIG_SITE = $(BR2_EXTERNAL_STRATURAOS_PATH)/package/stratura-config/src
STRATURA_CONFIG_SITE_METHOD = local
STRATURA_CONFIG_LICENSE = MIT

STRATURA_CONFIG_DEPENDENCIES = python3 network-manager

define STRATURA_CONFIG_INSTALL_TARGET_CMDS
	# Install config manager
	$(INSTALL) -D -m 0755 $(@D)/stratura-config \
		$(TARGET_DIR)/usr/bin/stratura-config

	# Install network manager module
	$(INSTALL) -D -m 0644 $(@D)/network_manager.py \
		$(TARGET_DIR)/usr/lib/stratura/network_manager.py

	# Install default configuration
	$(INSTALL) -d $(TARGET_DIR)/etc/stratura
	$(INSTALL) -D -m 0644 $(@D)/config.json \
		$(TARGET_DIR)/etc/stratura/config.json

	# Install NetworkManager config
	$(INSTALL) -d $(TARGET_DIR)/etc/NetworkManager/conf.d
	$(INSTALL) -D -m 0644 $(@D)/00-stratura-network.conf \
		$(TARGET_DIR)/etc/NetworkManager/conf.d/00-stratura-network.conf

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/stratura-config.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-config.service
endef

define STRATURA_CONFIG_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/stratura-config.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-config.service
endef

$(eval $(generic-package))
