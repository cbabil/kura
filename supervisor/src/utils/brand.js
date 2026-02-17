'use strict';

const fs = require('fs');

const BRAND_ENV_PATH = '/etc/falken/brand.env';

// Defaults must match scripts/common/brand-defaults.sh
const DEFAULTS = Object.freeze({
  BRAND_NAME: 'FalkenOS',
  BRAND_PREFIX: 'falken',
  BRAND_VERSION: '2.0',
  BRAND_API_ENDPOINT: 'https://api.falken.io',
  BRAND_WS_ENDPOINT: 'wss://api.falken.io/ws',
  BRAND_REGISTRY: 'registry.falken.io',
  BRAND_WS_HEARTBEAT_INTERVAL: '30000',
  BRAND_WS_HEARTBEAT_TIMEOUT: '90000',
  BRAND_WS_RECONNECT_BASE: '1000',
  BRAND_WS_RECONNECT_MAX: '60000',
});

function loadBrand(envPath = BRAND_ENV_PATH) {
  const result = { ...DEFAULTS };

  try {
    const raw = fs.readFileSync(envPath, 'utf8');
    for (const line of raw.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eqIdx = trimmed.indexOf('=');
      if (eqIdx < 1) continue;
      const key = trimmed.slice(0, eqIdx);
      let val = trimmed.slice(eqIdx + 1);
      // Strip surrounding quotes
      if ((val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      if (key in result) {
        result[key] = val;
      }
    }
  } catch (_err) {
    // brand.env missing (dev environment) -- use defaults
  }

  return Object.freeze(result);
}

const brand = loadBrand();

module.exports = { ...brand, loadBrand };
