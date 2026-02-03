STRATURA_MONITOR_VERSION = 1.0.0
STRATURA_MONITOR_SITE = $(BR2_EXTERNAL_STRATURAOS_PATH)/package/stratura-monitor/src
STRATURA_MONITOR_SITE_METHOD = local
STRATURA_MONITOR_LICENSE = MIT

STRATURA_MONITOR_DEPENDENCIES = python3

define STRATURA_MONITOR_INSTALL_TARGET_CMDS
	# Install monitor scripts
	$(INSTALL) -D -m 0644 $(@D)/system_monitor.py \
		$(TARGET_DIR)/usr/lib/stratura/system_monitor.py
	$(INSTALL) -D -m 0644 $(@D)/metrics_collector.py \
		$(TARGET_DIR)/usr/lib/stratura/metrics_collector.py
	$(INSTALL) -D -m 0644 $(@D)/health_monitor.py \
		$(TARGET_DIR)/usr/lib/stratura/health_monitor.py

	# Install launcher
	$(INSTALL) -D -m 0755 $(@D)/stratura-monitor \
		$(TARGET_DIR)/usr/bin/stratura-monitor

	# Install systemd service
	$(INSTALL) -D -m 0644 $(@D)/stratura-monitor.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-monitor.service
endef

define STRATURA_MONITOR_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/stratura-monitor.service \
		$(TARGET_DIR)/usr/lib/systemd/system/stratura-monitor.service
endef

$(eval $(generic-package))
