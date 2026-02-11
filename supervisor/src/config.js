'use strict';

const fs = require('fs');
const logger = require('./utils/logger');
const { PATHS, DEFAULTS } = require('./utils/constants');

const DEFAULT_CONFIG = Object.freeze({
  api_endpoint: DEFAULTS.API_ENDPOINT,
  poll_interval: DEFAULTS.POLL_INTERVAL,
  applications: [],
  logging: { level: DEFAULTS.LOG_LEVEL, file: `${PATHS.LOG_DIR}/supervisor.log` },
  storage: { docker_root: '/var/lib/docker', data_root: '/var/lib/stratura' },
  network: { api_port: DEFAULTS.PORT, metrics_port: 9999 },
  security: { tls_enabled: false, cert_path: PATHS.CERT_DIR, verify_images: true },
});

function loadConfig(configPath = PATHS.CONFIG) {
  try {
    const raw = fs.readFileSync(configPath, 'utf8');
    const parsed = JSON.parse(raw);
    logger.info({ configPath }, 'Configuration loaded');
    return { ...DEFAULT_CONFIG, ...parsed };
  } catch (err) {
    if (err.code === 'ENOENT') {
      logger.warn({ configPath }, 'Config file not found, using defaults');
    } else if (err instanceof SyntaxError) {
      logger.error({ configPath, err: err.message }, 'Invalid config JSON');
    } else {
      logger.error({ configPath, err: err.message }, 'Failed to read config');
    }
    return { ...DEFAULT_CONFIG };
  }
}

function loadSecurityConfig(configPath = PATHS.SECURITY_CONFIG) {
  const defaults = {
    container_security: {
      verify_signatures: true,
      allowed_registries: ['registry.stratura.io', 'docker.io'],
      seccomp_profile: 'default',
    },
    update_security: {
      verify_signatures: true,
      require_chain_of_trust: true,
      rollback_protection: true,
    },
  };

  try {
    const raw = fs.readFileSync(configPath, 'utf8');
    return { ...defaults, ...JSON.parse(raw) };
  } catch (_err) {
    logger.warn({ configPath }, 'Security config not found, using defaults');
    return defaults;
  }
}

module.exports = { loadConfig, loadSecurityConfig };
