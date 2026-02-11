'use strict';

const PATHS = Object.freeze({
  CONFIG: '/etc/stratura/supervisor-config.json',
  SECURITY_CONFIG: '/etc/stratura/security-config.json',
  STATE_FILE: '/var/lib/stratura/device-state.json',
  STATE_LOCK: '/var/lib/stratura/device-state.lock',
  UPDATE_LOCK: '/var/lib/stratura/update.lock',
  VOLUMES_DIR: '/var/lib/stratura/volumes',
  LOG_DIR: '/var/log/stratura',
  CERT_DIR: '/etc/stratura/certs',
});

const DEFAULTS = Object.freeze({
  PORT: 48484,
  POLL_INTERVAL: 60,
  API_ENDPOINT: 'https://api.stratura.io',
  MONITOR_CRON: '*/30 * * * * *',
  LOG_LEVEL: 'info',
});

const LABELS = Object.freeze({
  MANAGED: 'io.stratura.managed',
  APP_NAME: 'io.stratura.app.name',
  APP_VERSION: 'io.stratura.version',
});

const UPDATE_STATES = Object.freeze({
  IDLE: 'idle',
  DOWNLOADING: 'downloading',
  APPLYING: 'applying',
  VERIFYING: 'verifying',
  COMPLETED: 'completed',
  FAILED: 'failed',
});

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
};
