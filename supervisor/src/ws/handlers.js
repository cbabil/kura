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
    connection.setAuthenticated(true);
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
    logger.error({ action: msg.action, err: err.message }, 'Command failed');
    connection.send(createError(msg.id, err));
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
    supervisor_version: process.env.npm_package_version || '1.0.0',
    metrics: metrics || {},
  };
}

async function handleDeviceState() {
  return stateManager.load();
}

async function handleDeviceReboot() {
  logger.info('Reboot requested via WebSocket');
  setTimeout(() => {
    execFile('reboot', (err) => {
      if (err) { logger.error({ err: err.message }, 'Reboot failed'); }
    });
  }, 1000);
  return { status: 'Reboot initiated' };
}

async function handleDeviceShutdown() {
  logger.info('Shutdown requested via WebSocket');
  setTimeout(() => {
    execFile('shutdown', ['-h', 'now'], (err) => {
      if (err) { logger.error({ err: err.message }, 'Shutdown failed'); }
    });
  }, 1000);
  return { status: 'Shutdown initiated' };
}

async function handleContainerList() {
  return containerManager.listContainers();
}

async function handleContainerStart(payload) {
  requireString(payload.id, 'payload.id');
  await containerManager.startContainer(payload.id);
  return { status: 'started', id: payload.id };
}

async function handleContainerStop(payload) {
  requireString(payload.id, 'payload.id');
  await containerManager.stopContainer(payload.id);
  return { status: 'stopped', id: payload.id };
}

async function handleContainerRestart(payload) {
  requireString(payload.id, 'payload.id');
  await containerManager.restartContainer(payload.id);
  return { status: 'restarted', id: payload.id };
}

async function handleContainerRemove(payload) {
  requireString(payload.id, 'payload.id');
  await containerManager.removeContainer(payload.id, true);
  return { status: 'removed', id: payload.id };
}

async function handleContainerLogs(payload) {
  requireString(payload.id, 'payload.id');
  const tail = Number.isInteger(payload.tail) && payload.tail > 0
    ? Math.min(payload.tail, 10000)
    : 100;
  const logs = await containerManager.getLogs(payload.id, tail);
  return { logs };
}

async function handleUpdateTrigger(payload) {
  requireString(payload.containerId, 'payload.containerId');
  requireString(payload.image, 'payload.image');
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

module.exports = { handleMessage, handleCommand, COMMAND_MAP };
