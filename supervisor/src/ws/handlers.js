'use strict';

const { execFile } = require('child_process');
const os = require('os');
const logger = require('../utils/logger');
const { ENV_PREFIX } = require('../utils/constants');
const { validateInbound, createResponse, createError } = require('./protocol');
const connection = require('./connection');
const containerManager = require('../services/container-manager');
const updateManager = require('../services/update-manager');
const stateManager = require('../services/state-manager');
const monitor = require('../services/monitor');
const securityManager = require('../services/security-manager');
const { version: SUPERVISOR_VERSION } = require('../../package.json');

const RATE_LIMIT_WINDOW = 60000;
const RATE_LIMIT_MAX = 60;
const RATE_LIMIT_CAP = RATE_LIMIT_MAX * 2;
const commandTimestamps = [];
const CONTAINER_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/;

function checkRateLimit() {
  const now = Date.now();
  const cutoff = now - RATE_LIMIT_WINDOW;
  let i = 0;
  while (i < commandTimestamps.length && commandTimestamps[i] <= cutoff) { i++; }
  if (i > 0) { commandTimestamps.splice(0, i); }
  if (commandTimestamps.length > RATE_LIMIT_CAP) {
    commandTimestamps.length = RATE_LIMIT_MAX;
  }
  if (commandTimestamps.length >= RATE_LIMIT_MAX) {
    return false;
  }
  commandTimestamps.push(now);
  return true;
}

function _resetRateLimit() {
  commandTimestamps.length = 0;
}

const COMMAND_MAP = {
  'device.info': handleDeviceInfo,
  'device.state': handleDeviceState,
  'device.reboot': handleDeviceReboot,
  'device.shutdown': handleDeviceShutdown,
  'container.list': handleContainerList,
  'container.start': handleContainerStart,
  'container.stop': handleContainerStop,
  'container.restart': handleContainerRestart,
  'container.remove': handleContainerRemove,
  'container.logs': handleContainerLogs,
  'update.trigger': handleUpdateTrigger,
  'update.status': handleUpdateStatus,
};

function requireString(value, name) {
  if (!value || typeof value !== 'string') {
    throw new Error(`${name} is required and must be a string`);
  }
}

function requireContainerId(value) {
  requireString(value, 'payload.id');
  if (value.length > 128 || !CONTAINER_ID_RE.test(value)) {
    throw new Error('Invalid container ID format');
  }
}

function handleMessage(raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch (_err) {
    logger.warn('Received non-JSON message, ignoring');
    return;
  }

  const { valid, error } = validateInbound(msg);
  if (!valid) {
    logger.warn({ error }, 'Invalid inbound message');
    if (msg.id) { connection.send(createError(msg.id, error)); }
    return;
  }

  // Handle auth acknowledgment from server
  if (msg.type === 'response' && msg.success === true && msg.payload?.auth === true) {
    const expectedId = connection.getPendingAuthId();
    if (!expectedId) {
      logger.warn('Received auth response but no auth request pending, ignoring');
      return;
    }
    if (msg.id !== expectedId) {
      logger.warn({ expected: expectedId, received: msg.id }, 'Auth response ID mismatch, ignoring');
      return;
    }
    connection.setAuthenticated(true);
    connection.clearPendingAuthId();
    logger.info('Authentication acknowledged by server');
    return;
  }

  if (msg.type === 'command') {
    if (!connection.isAuthenticated()) {
      logger.warn({ action: msg.action }, 'Command received before authentication, ignoring');
      connection.send(createError(msg.id, 'Not authenticated'));
      return;
    }
    handleCommand(msg).catch((err) => {
      logger.error({ err: err.message }, 'Unexpected command handler error');
    });
  }
}

async function handleCommand(msg) {
  if (!checkRateLimit()) {
    logger.warn({ action: msg.action }, 'Rate limit exceeded');
    connection.send(createError(msg.id, 'Rate limit exceeded (60 commands/minute)'));
    return;
  }
  const handler = COMMAND_MAP[msg.action];
  if (!handler) {
    logger.warn({ action: msg.action }, 'Unknown command action');
    connection.send(createError(msg.id, `Unknown action: ${msg.action}`));
    return;
  }

  try {
    const result = await handler(msg.payload || {});
    connection.send(createResponse(msg.id, result));
  } catch (err) {
    logger.error({ action: msg.action, err: err.message, stack: err.stack }, 'Command failed');
    connection.send(createError(msg.id, `Command ${msg.action} failed`));
  }
}

async function handleDeviceInfo() {
  const metrics = monitor.getLastMetrics();
  return {
    hostname: os.hostname(),
    platform: os.platform(),
    arch: os.arch(),
    uptime: os.uptime(),
    device_id: process.env[`${ENV_PREFIX}_DEVICE_ID`] || 'unknown',
    supervisor_version: SUPERVISOR_VERSION,
    metrics: metrics || {},
  };
}

async function handleDeviceState() {
  return stateManager.load();
}

async function handleDeviceReboot() {
  logger.info('Reboot requested via WebSocket');
  setTimeout(() => {
    execFile('sudo', ['systemctl', 'reboot'], (err) => {
      if (err) { logger.error({ err: err.message }, 'Reboot failed'); }
    });
  }, 1000);
  return { status: 'Reboot initiated' };
}

async function handleDeviceShutdown() {
  logger.info('Shutdown requested via WebSocket');
  setTimeout(() => {
    execFile('sudo', ['systemctl', 'poweroff'], (err) => {
      if (err) { logger.error({ err: err.message }, 'Shutdown failed'); }
    });
  }, 1000);
  return { status: 'Shutdown initiated' };
}

async function handleContainerList() {
  return containerManager.listContainers();
}

async function handleContainerStart(payload) {
  requireContainerId(payload.id);
  await containerManager.startContainer(payload.id);
  return { status: 'started', id: payload.id };
}

async function handleContainerStop(payload) {
  requireContainerId(payload.id);
  await containerManager.stopContainer(payload.id);
  return { status: 'stopped', id: payload.id };
}

async function handleContainerRestart(payload) {
  requireContainerId(payload.id);
  await containerManager.restartContainer(payload.id);
  return { status: 'restarted', id: payload.id };
}

async function handleContainerRemove(payload) {
  requireContainerId(payload.id);
  await containerManager.removeContainer(payload.id, true);
  return { status: 'removed', id: payload.id };
}

async function handleContainerLogs(payload) {
  requireContainerId(payload.id);
  const tail = Number.isInteger(payload.tail) && payload.tail > 0
    ? Math.min(payload.tail, 10000)
    : 100;
  const logs = await containerManager.getLogs(payload.id, tail);
  return { logs };
}

async function handleUpdateTrigger(payload) {
  requireString(payload.containerId, 'payload.containerId');
  requireString(payload.image, 'payload.image');
  const imageCheck = securityManager.validateImage(payload.image);
  if (!imageCheck.valid) {
    throw new Error(`Image rejected: ${imageCheck.reason}`);
  }
  await updateManager.triggerUpdate(payload.containerId, payload.image);
  return {
    status: 'Update triggered',
    containerId: payload.containerId,
    image: payload.image,
  };
}

async function handleUpdateStatus() {
  return updateManager.getUpdateStatus();
}

module.exports = { handleMessage, handleCommand, COMMAND_MAP, _resetRateLimit };
