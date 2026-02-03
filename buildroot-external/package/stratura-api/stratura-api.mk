STRATURA_API_VERSION = 1.0.0
STRATURA_API_SITE = $(BR2_EXTERNAL_STRATURAOS_PATH)/package/stratura-api/src
STRATURA_API_SITE_METHOD = local
STRATURA_API_LICENSE = MIT

STRATURA_API_DEPENDENCIES = python3 stratura-supervisor

define STRATURA_API_INSTALL_TARGET_CMDS
	# Install API server
	$(INSTALL) -D -m 0755 $(@D)/api_server.py \
		$(TARGET_DIR)/usr/lib/stratura/api_server.py

	# Install API client library
	$(INSTALL) -D -m 0644 $(@D)/api_client.py \
		$(TARGET_DIR)/usr/lib/stratura/api_client.py

	# Install launcher script
	$(INSTALL) -D -m 0755 $(@D)/stratura-api \
		$(TARGET_DIR)/usr/bin/stratura-api

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/stratura-api.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-api.service
endef

define STRATURA_API_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/stratura-api.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-api.service
endef

$(eval $(generic-package))
