'use strict';

const { LABELS, ENV_PREFIX } = require('../utils/constants');

function buildSecurityOpts(config) {
  const privileged = config.privileged || false;
  const seccomp = privileged ? 'seccomp=unconfined' : 'seccomp=default';
  return {
    securityOpt: ['no-new-privileges', seccomp],
    capDrop: ['ALL'],
    capAdd: config.capabilities || [],
    readOnly: config.read_only || false,
  };
}

function buildResourceOpts(config) {
  const res = config.resources || {};
  return {
    memory: parseMemory(res.memory || '256m'),
    cpuShares: res.cpu_shares || 1024,
  };
}

function parseMemory(memStr) {
  const match = String(memStr).match(/^(\d+)([mgk]?)$/i);
  if (!match) { return 256 * 1024 * 1024; }
  const num = parseInt(match[1], 10);
  const unit = (match[2] || 'm').toLowerCase();
  const multipliers = { k: 1024, m: 1024 * 1024, g: 1024 * 1024 * 1024 };
  return num * (multipliers[unit] || 1024 * 1024);
}

function buildNetworkOpts(config) {
  const net = config.network || {};
  if (net.type === 'host') {
    return { networkMode: 'host', portBindings: {} };
  }
  const portBindings = {};
  for (const p of net.ports || []) {
    if (typeof p === 'string') {
      const [host, rest] = p.split(':');
      portBindings[`${rest}/tcp`] = [{ HostPort: host }];
    } else if (p && typeof p === 'object') {
      const proto = p.protocol || 'tcp';
      portBindings[`${p.container}/${proto}`] = [{ HostPort: String(p.host) }];
    }
  }
  return { networkMode: net.mode || 'bridge', portBindings };
}

function buildEnv(config) {
  const base = {
    [`${ENV_PREFIX}_APP_NAME`]: config.name,
    [`${ENV_PREFIX}_APP_VERSION`]: config.version || 'latest',
    [`${ENV_PREFIX}_DEVICE_ID`]: process.env[`${ENV_PREFIX}_DEVICE_ID`] || 'unknown',
  };
  const merged = { ...base, ...(config.environment || {}) };
  return Object.entries(merged).map(([k, v]) => `${k}=${v}`);
}

function buildBinds(config) {
  return (config.volumes || []).map((vol) => {
    if (typeof vol === 'string') { return vol; }
    const mode = vol.mode || 'rw';
    return `${vol.host_path}:${vol.container_path}:${mode}`;
  });
}

function buildLabels(config) {
  return {
    [LABELS.MANAGED]: 'true',
    [LABELS.APP_NAME]: config.name,
    [LABELS.APP_VERSION]: config.version || 'latest',
  };
}

function buildHealthcheck(config) {
  const hc = config.healthcheck;
  if (!hc || !hc.cmd) { return null; }
  return {
    Test: ['CMD-SHELL', hc.cmd],
    Interval: parseDuration(hc.interval || '30s'),
    Timeout: parseDuration(hc.timeout || '5s'),
    Retries: hc.retries || 3,
  };
}

function parseDuration(str) {
  const match = String(str).match(/^(\d+)(s|ms|m)?$/);
  if (!match) { return 30 * 1e9; }
  const num = parseInt(match[1], 10);
  const unit = match[2] || 's';
  const ns = { ms: 1e6, s: 1e9, m: 60 * 1e9 };
  return num * (ns[unit] || 1e9);
}

module.exports = {
  buildSecurityOpts,
  buildResourceOpts,
  buildNetworkOpts,
  buildEnv,
  buildBinds,
  buildLabels,
  buildHealthcheck,
};
