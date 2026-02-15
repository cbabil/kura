'use strict';

const crypto = require('crypto');
const os = require('os');
const { ENV_PREFIX } = require('../utils/constants');

const VALID_TYPES = ['command', 'response', 'telemetry', 'log', 'auth', 'heartbeat'];

function createId() {
  return crypto.randomUUID();
}

function createAuth() {
  return {
    type: 'auth',
    id: createId(),
    payload: {
      device_id: process.env[`${ENV_PREFIX}_DEVICE_ID`] || 'unknown',
      api_key: process.env[`${ENV_PREFIX}_API_KEY`] || '',
      hostname: os.hostname(),
      platform: os.platform(),
      arch: os.arch(),
    },
  };
}

function createResponse(id, payload) {
  return {
    type: 'response',
    id,
    success: true,
    payload,
  };
}

function createError(id, err) {
  return {
    type: 'response',
    id,
    success: false,
    error: typeof err === 'string' ? err : err.message,
  };
}

function createTelemetry(metrics) {
  return {
    type: 'telemetry',
    id: createId(),
    payload: metrics,
  };
}

function createHeartbeat() {
  return {
    type: 'heartbeat',
    id: createId(),
    payload: { uptime: process.uptime() },
  };
}

function validateInbound(msg) {
  if (!msg || typeof msg !== 'object' || Array.isArray(msg)) {
    return { valid: false, error: 'Message must be a JSON object' };
  }
  if (!msg.type || !VALID_TYPES.includes(msg.type)) {
    return { valid: false, error: `Invalid message type: ${msg.type}` };
  }
  if (msg.type === 'command' && !msg.action) {
    return { valid: false, error: 'Command messages require an action field' };
  }
  if (msg.type === 'command' && !msg.id) {
    return { valid: false, error: 'Command messages require an id field' };
  }
  return { valid: true };
}

module.exports = {
  createAuth,
  createResponse,
  createError,
  createTelemetry,
  createHeartbeat,
  validateInbound,
  VALID_TYPES,
};
