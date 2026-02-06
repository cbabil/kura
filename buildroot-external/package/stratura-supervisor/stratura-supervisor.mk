STRATURA_SUPERVISOR_VERSION = 1.0.0
STRATURA_SUPERVISOR_SITE = $(BR2_EXTERNAL_STRATURAOS_PATH)/package/stratura-supervisor/src
STRATURA_SUPERVISOR_SITE_METHOD = local
STRATURA_SUPERVISOR_LICENSE = MIT
STRATURA_SUPERVISOR_LICENSE_FILES = LICENSE

STRATURA_SUPERVISOR_DEPENDENCIES = python3 python-requests docker-engine docker-cli

define STRATURA_SUPERVISOR_INSTALL_TARGET_CMDS
	# Install main supervisor script
	$(INSTALL) -D -m 0755 $(@D)/supervisor \
		$(TARGET_DIR)/usr/bin/stratura-supervisor

	# Install Python modules
	$(INSTALL) -d $(TARGET_DIR)/usr/lib/stratura
	touch $(TARGET_DIR)/usr/lib/stratura/__init__.py
	$(INSTALL) -D -m 0644 $(@D)/container_manager.py \
		$(TARGET_DIR)/usr/lib/stratura/container_manager.py
	$(INSTALL) -D -m 0644 $(@D)/security_manager.py \
		$(TARGET_DIR)/usr/lib/stratura/security_manager.py
	$(INSTALL) -D -m 0644 $(@D)/state_manager.py \
		$(TARGET_DIR)/usr/lib/stratura/state_manager.py
	$(INSTALL) -D -m 0644 $(@D)/provisioning_manager.py \
		$(TARGET_DIR)/usr/lib/stratura/provisioning_manager.py

	# Install healthcheck script
	$(INSTALL) -D -m 0755 $(@D)/supervisor-healthcheck \
		$(TARGET_DIR)/usr/bin/stratura-healthcheck

	# Install configuration
	$(INSTALL) -d $(TARGET_DIR)/etc/stratura
	$(INSTALL) -D -m 0644 $(@D)/supervisor-config.json \
		$(TARGET_DIR)/etc/stratura/supervisor-config.json
	$(INSTALL) -D -m 0644 $(@D)/security-config.json \
		$(TARGET_DIR)/etc/stratura/security-config.json

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/supervisor.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-supervisor.service
endef

define STRATURA_SUPERVISOR_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/supervisor.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-supervisor.service
endef

$(eval $(generic-package))
