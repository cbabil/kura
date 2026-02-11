'use strict';

const fs = require('fs');
const path = require('path');
const lockfile = require('proper-lockfile');
const logger = require('../utils/logger');
const { PATHS } = require('../utils/constants');

const STATE_FILE = PATHS.STATE_FILE;
const STATE_DIR = path.dirname(STATE_FILE);

function getDefaultState() {
  return {
    version: '0.0.1', boot_count: 0, last_boot: null,
    update_status: { last_update: null, current_version: '0.0.1', update_state: 'idle' },
    network_status: { connected: false, interface: null, ip_address: null },
    containers: {},
    provisioning: { completed: false, timestamp: null },
  };
}

function ensureDir() {
  if (!fs.existsSync(STATE_DIR)) { fs.mkdirSync(STATE_DIR, { recursive: true }); }
}

async function withLock(fn) {
  let release;
  try {
    release = await lockfile.lock(STATE_FILE, { retries: 3 });
    return await fn();
  } finally {
    if (release) { await release(); }
  }
}

async function load() {
  ensureDir();
  if (!fs.existsSync(STATE_FILE)) {
    const state = getDefaultState();
    await save(state);
    return state;
  }
  try {
    return await withLock(() => JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')));
  } catch (err) {
    logger.error({ err: err.message }, 'Failed to load state');
    return getDefaultState();
  }
}

async function save(state) {
  ensureDir();
  const tmpFile = `${STATE_FILE}.tmp`;
  if (!fs.existsSync(STATE_FILE)) {
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    return;
  }
  try {
    await withLock(() => {
      fs.writeFileSync(tmpFile, JSON.stringify(state, null, 2));
      fs.renameSync(tmpFile, STATE_FILE);
    });
  } catch (err) {
    logger.error({ err: err.message }, 'Failed to save state');
    throw err;
  }
}

async function update(fn) {
  const state = await load();
  const updated = fn(state);
  await save(updated);
  return updated;
}

async function updateBootCount() {
  return update((s) => ({ ...s, boot_count: s.boot_count + 1, last_boot: new Date().toISOString() }));
}

async function updateNetworkStatus(status) {
  return update((s) => ({ ...s, network_status: { ...s.network_status, ...status } }));
}

async function updateContainerStatus(container, status) {
  return update((s) => ({ ...s, containers: { ...s.containers, [container]: status } }));
}

async function setProvisioningComplete() {
  return update((s) => ({ ...s, provisioning: { completed: true, timestamp: new Date().toISOString() } }));
}

module.exports = {
  load, save, getDefaultState,
  updateBootCount, updateNetworkStatus, updateContainerStatus, setProvisioningComplete,
};
