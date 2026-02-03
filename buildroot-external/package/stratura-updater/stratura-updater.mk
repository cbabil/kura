STRATURA_UPDATER_VERSION = 1.0.0
STRATURA_UPDATER_SITE = $(BR2_EXTERNAL_STRATURAOS_PATH)/package/stratura-updater/src
STRATURA_UPDATER_SITE_METHOD = local
STRATURA_UPDATER_LICENSE = MIT

STRATURA_UPDATER_DEPENDENCIES = python3 rauc

define STRATURA_UPDATER_INSTALL_TARGET_CMDS
	# Install update client
	$(INSTALL) -D -m 0755 $(@D)/update-client \
		$(TARGET_DIR)/usr/bin/stratura-updater

	# Install update workflow
	$(INSTALL) -D -m 0644 $(@D)/update-workflow.py \
		$(TARGET_DIR)/usr/lib/stratura/update_workflow.py

	# Install RAUC configuration
	$(INSTALL) -d $(TARGET_DIR)/etc/rauc
	$(INSTALL) -D -m 0644 $(@D)/system.conf \
		$(TARGET_DIR)/etc/rauc/system.conf

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/stratura-updater.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-updater.service
endef

define STRATURA_UPDATER_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/stratura-updater.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-updater.service
endef

$(eval $(generic-package))
