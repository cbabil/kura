'use strict';

const logger = require('../utils/logger');
const config = require('../config');

let securityConfig = null;

function getConfig() {
  if (!securityConfig) {
    securityConfig = config.loadSecurityConfig();
  }
  return securityConfig;
}

function getSecurityOpts(containerConfig) {
  const privileged = containerConfig.privileged || false;
  const seccomp = privileged ? 'seccomp=unconfined' : 'seccomp=default';

  return {
    securityOpt: ['no-new-privileges', seccomp],
    capDrop: ['ALL'],
    capAdd: containerConfig.capabilities || [],
    readOnly: containerConfig.read_only || false,
  };
}

function validateImage(image) {
  const config = getConfig();
  const allowed = config.container_security.allowed_registries;

  if (!config.container_security.verify_signatures) {
    return { valid: true, reason: 'Signature verification disabled' };
  }

  const registry = extractRegistry(image);

  const isAllowed = allowed.some((r) => registry === r || registry.endsWith(`.${r}`));
  if (!isAllowed) {
    logger.warn({ image, registry, allowed }, 'Image from disallowed registry');
    return { valid: false, reason: `Registry '${registry}' not in allowed list` };
  }

  return { valid: true, reason: 'Registry allowed' };
}

function extractRegistry(image) {
  const parts = image.split('/');
  if (parts.length === 1) { return 'docker.io'; }
  if (parts[0].includes('.') || parts[0].includes(':')) {
    return parts[0];
  }
  return 'docker.io';
}

function auditContainerSecurity(inspectData) {
  const findings = [];
  const hostConfig = inspectData.HostConfig || {};

  if (hostConfig.Privileged) {
    findings.push({ severity: 'critical', issue: 'Container running in privileged mode' });
  }

  if (hostConfig.NetworkMode === 'host') {
    findings.push({ severity: 'warning', issue: 'Container using host network' });
  }

  if (hostConfig.PidMode === 'host') {
    findings.push({ severity: 'critical', issue: 'Container sharing host PID namespace' });
  }

  const secOpts = hostConfig.SecurityOpt || [];
  if (!secOpts.some((o) => o.includes('no-new-privileges'))) {
    findings.push({ severity: 'warning', issue: 'no-new-privileges not set' });
  }

  const capAdd = hostConfig.CapAdd || [];
  const dangerousCaps = ['SYS_ADMIN', 'NET_ADMIN', 'SYS_PTRACE'];
  for (const cap of capAdd) {
    if (dangerousCaps.includes(cap)) {
      findings.push({ severity: 'warning', issue: `Dangerous capability: ${cap}` });
    }
  }

  if (!hostConfig.ReadonlyRootfs) {
    findings.push({ severity: 'info', issue: 'Root filesystem is writable' });
  }

  if (!hostConfig.Memory || hostConfig.Memory === 0) {
    findings.push({ severity: 'warning', issue: 'No memory limit set' });
  }

  logger.info({ containerName: inspectData.Name, findings: findings.length }, 'Security audit complete');
  return findings;
}

function _resetConfig() {
  securityConfig = null;
}

module.exports = {
  getSecurityOpts,
  validateImage,
  auditContainerSecurity,
  _resetConfig,
};
