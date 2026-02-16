'use strict';

const WebSocket = require('ws');
const logger = require('../utils/logger');
const { DEFAULTS } = require('../utils/constants');
const { createAuth, createHeartbeat } = require('./protocol');

let ws = null;
let heartbeatTimer = null;
let heartbeatTimeout = null;
let reconnectAttempt = 0;
let reconnectTimer = null;
let onMessageHandler = null;
let shuttingDown = false;
let authenticated = false;
let pendingAuthId = null;

function getEndpoint() {
  const endpoint = process.env.WS_ENDPOINT || DEFAULTS.WS_ENDPOINT;
  if (!endpoint.startsWith('wss://')) {
    logger.warn({ endpoint }, 'WebSocket endpoint does not use TLS');
  }
  return endpoint;
}

function connect(messageHandler) {
  // Clean up any existing connection before creating a new one
  if (ws) {
    stopHeartbeat();
    ws.removeAllListeners();
    if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
      ws.close();
    }
    ws = null;
  }

  onMessageHandler = messageHandler;
  shuttingDown = false;
  authenticated = false;
  const endpoint = getEndpoint();

  logger.info({ endpoint }, 'Connecting to cloud');
  ws = new WebSocket(endpoint, { maxPayload: 128 * 1024 });

  ws.on('open', () => {
    logger.info({ endpoint }, 'WebSocket connected');
    reconnectAttempt = 0;
    const authMsg = createAuth();
    pendingAuthId = authMsg.id;
    send(authMsg);
    startHeartbeat();
  });

  ws.on('message', (data) => {
    resetHeartbeatTimeout();
    if (onMessageHandler) {
      onMessageHandler(data.toString());
    }
  });

  ws.on('close', (code, reason) => {
    logger.warn({ code, reason: reason.toString() }, 'WebSocket closed');
    authenticated = false;
    pendingAuthId = null;
    stopHeartbeat();
    if (!shuttingDown) {
      scheduleReconnect();
    }
  });

  ws.on('error', (err) => {
    logger.error({ err: err.message }, 'WebSocket error');
  });

  ws.on('pong', () => {
    resetHeartbeatTimeout();
  });

  return ws;
}

function send(msg) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    logger.warn('WebSocket not open, dropping message');
    return false;
  }
  try {
    ws.send(JSON.stringify(msg));
  } catch (err) {
    logger.error({ err: err.message }, 'Failed to send WebSocket message');
    return false;
  }
  return true;
}

function startHeartbeat() {
  const interval = DEFAULTS.WS_HEARTBEAT_INTERVAL;

  heartbeatTimer = setInterval(() => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.ping();
      send(createHeartbeat());
    }
  }, interval);

  resetHeartbeatTimeout();
}

function resetHeartbeatTimeout() {
  if (heartbeatTimeout) { clearTimeout(heartbeatTimeout); }
  heartbeatTimeout = setTimeout(() => {
    logger.warn('Heartbeat timeout, closing connection');
    if (ws) { ws.terminate(); }
  }, DEFAULTS.WS_HEARTBEAT_TIMEOUT);
}

function stopHeartbeat() {
  if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
  if (heartbeatTimeout) { clearTimeout(heartbeatTimeout); heartbeatTimeout = null; }
}

function scheduleReconnect() {
  const base = DEFAULTS.WS_RECONNECT_BASE;
  const max = DEFAULTS.WS_RECONNECT_MAX;
  const jitter = Math.random() * 1000;
  const delay = Math.min(base * (2 ** reconnectAttempt), max) + jitter;

  reconnectAttempt = Math.min(reconnectAttempt + 1, 100);
  const logLevel = reconnectAttempt > 10 ? 'error' : 'info';
  logger[logLevel]({ attempt: reconnectAttempt, delay: Math.round(delay) }, 'Scheduling reconnect');

  reconnectTimer = setTimeout(() => {
    connect(onMessageHandler);
  }, delay);
}

function close() {
  shuttingDown = true;
  authenticated = false;
  pendingAuthId = null;
  stopHeartbeat();
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  if (ws) {
    ws.close(1000, 'Supervisor shutting down');
    ws = null;
  }
}

function isConnected() {
  return ws !== null && ws.readyState === WebSocket.OPEN;
}

function isAuthenticated() {
  return authenticated;
}

function setAuthenticated(value) {
  authenticated = value;
}

function getPendingAuthId() {
  return pendingAuthId;
}

function clearPendingAuthId() {
  pendingAuthId = null;
}

module.exports = { connect, send, close, isConnected, isAuthenticated, setAuthenticated, getPendingAuthId, clearPendingAuthId };
