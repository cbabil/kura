'use strict';

const lockfile = require('proper-lockfile');
const fs = require('fs');
const path = require('path');
const logger = require('../utils/logger');
const { PATHS, UPDATE_STATES } = require('../utils/constants');
const containerManager = require('./container-manager');

const LOCK_FILE = PATHS.UPDATE_LOCK;
const LOCK_DIR = path.dirname(LOCK_FILE);
let currentState = UPDATE_STATES.IDLE;
let updateError = null;
let updateProgress = null;

function getUpdateStatus() {
  return { state: currentState, error: updateError, progress: updateProgress };
}

function setState(state, error = null) {
  currentState = state;
  updateError = error;
  logger.info({ state, error }, 'Update state changed');
}

async function acquireLock() {
  if (!fs.existsSync(LOCK_DIR)) { fs.mkdirSync(LOCK_DIR, { recursive: true }); }
  if (!fs.existsSync(LOCK_FILE)) { fs.writeFileSync(LOCK_FILE, ''); }
  const release = await lockfile.lock(LOCK_FILE, { retries: 3 });
  logger.info('Update lock acquired');
  return release;
}

async function releaseLock(release) {
  if (typeof release === 'function') { await release(); }
}

async function checkForUpdates(config) {
  if (currentState !== UPDATE_STATES.IDLE) {
    return { available: false, reason: `Update in progress: ${currentState}` };
  }
  for (const app of config.applications || []) {
    if (app.image) { logger.info({ image: app.image }, 'Checking for update'); }
  }
  return { available: false, reason: 'No updates available' };
}

async function triggerUpdate(containerId, newImage) {
  if (currentState !== UPDATE_STATES.IDLE) {
    throw new Error(`Cannot update while in state: ${currentState}`);
  }
  // Guarded inspect: refuses containers the supervisor did not create (e.g.
  // Tomo's) before pulling anything, so a refused update never reaches rollback.
  const info = await containerManager.inspectContainer(containerId);
  let release = null;
  let oldImage = null;
  try {
    release = await acquireLock();
    setState(UPDATE_STATES.DOWNLOADING);
    updateProgress = { containerId, newImage, step: 'pulling' };
    await containerManager.pullImage(newImage);

    setState(UPDATE_STATES.APPLYING);
    updateProgress = { ...updateProgress, step: 'stopping' };
    oldImage = info.Config.Image;
    await containerManager.stopContainer(containerId);
    await containerManager.removeContainer(containerId);

    updateProgress = { ...updateProgress, step: 'starting' };
    const name = info.Name.replace(/^\//, '');
    await containerManager.createContainer({ name, image: newImage, restart_policy: 'always' });

    setState(UPDATE_STATES.VERIFYING);
    setState(UPDATE_STATES.COMPLETED);
    updateProgress = { ...updateProgress, step: 'done' };
    logger.info({ containerId, newImage }, 'Update completed');
  } catch (err) {
    setState(UPDATE_STATES.FAILED, err.message);
    logger.error({ err: err.message, containerId, newImage }, 'Update failed');
    if (oldImage) {
      await rollback(containerId, oldImage).catch((e) => {
        logger.error({ err: e.message }, 'Rollback also failed');
      });
    }
    throw err;
  } finally {
    await releaseLock(release);
  }
}

async function rollback(containerId, oldImage) {
  logger.warn({ containerId, oldImage }, 'Rolling back update');
  await containerManager.stopContainer(containerId).catch(() => {});
  await containerManager.removeContainer(containerId, true).catch(() => {});
  await containerManager.createContainer({ name: containerId, image: oldImage, restart_policy: 'always' });
  logger.info({ containerId, oldImage }, 'Rollback completed');
}

function resetState() {
  setState(UPDATE_STATES.IDLE);
  updateProgress = null;
}

module.exports = {
  getUpdateStatus, checkForUpdates, triggerUpdate,
  rollback, acquireLock, releaseLock, resetState,
};
