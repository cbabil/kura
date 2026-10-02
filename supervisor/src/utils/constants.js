'use strict';

const brand = require('./brand');

const prefix = brand.BRAND_PREFIX;

const PATHS = Object.freeze({
  // Both are installed by the build: the overlay ships supervisor-config.json,
  // os-security ships hardening.json (same schema as the security defaults)
  CONFIG: `/etc/${prefix}/supervisor-config.json`,
  SECURITY_CONFIG: `/etc/${prefix}/security/hardening.json`,
  STATE_FILE: `/var/lib/${prefix}/device-state.json`,
  STATE_LOCK: `/var/lib/${prefix}/device-state.lock`,
  UPDATE_LOCK: `/var/lib/${prefix}/update.lock`,
  VOLUMES_DIR: `/var/lib/${prefix}/volumes`,
  LOG_DIR: `/var/log/${prefix}`,
  CERT_DIR: `/etc/${prefix}/certs`,
});

const DEFAULTS = Object.freeze({
  POLL_INTERVAL: 60,
  API_ENDPOINT: brand.BRAND_API_ENDPOINT,
  WS_ENDPOINT: brand.BRAND_WS_ENDPOINT,
  WS_HEARTBEAT_INTERVAL: parseInt(brand.BRAND_WS_HEARTBEAT_INTERVAL, 10),
  WS_HEARTBEAT_TIMEOUT: parseInt(brand.BRAND_WS_HEARTBEAT_TIMEOUT, 10),
  WS_RECONNECT_BASE: parseInt(brand.BRAND_WS_RECONNECT_BASE, 10),
  WS_RECONNECT_MAX: parseInt(brand.BRAND_WS_RECONNECT_MAX, 10),
  TELEMETRY_CRON: '*/30 * * * * *',
  LOG_LEVEL: 'info',
});

const LABELS = Object.freeze({
  MANAGED: `io.${prefix}.managed`,
  APP_NAME: `io.${prefix}.app.name`,
  APP_VERSION: `io.${prefix}.version`,
});

const UPDATE_STATES = Object.freeze({
  IDLE: 'idle',
  DOWNLOADING: 'downloading',
  APPLYING: 'applying',
  VERIFYING: 'verifying',
  COMPLETED: 'completed',
  FAILED: 'failed',
});

const ENV_PREFIX = prefix.toUpperCase();

const THRESHOLDS = Object.freeze({
  CPU_WARNING: 80,
  CPU_CRITICAL: 95,
  MEMORY_WARNING: 80,
  MEMORY_CRITICAL: 95,
  DISK_WARNING: 80,
  DISK_CRITICAL: 95,
  TEMP_CRITICAL: 85,
});

module.exports = {
  PATHS,
  DEFAULTS,
  LABELS,
  UPDATE_STATES,
  THRESHOLDS,
  ENV_PREFIX,
};
