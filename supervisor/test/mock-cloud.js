#!/usr/bin/env node
'use strict';

/**
 * Mock cloud WebSocket server for testing the supervisor locally.
 *
 * Usage:
 *   node test/mock-cloud.js
 *
 * Then in another terminal:
 *   WS_ENDPOINT=ws://localhost:8080/ws node src/index.js
 *
 * The server accepts auth, prints telemetry, and provides an interactive
 * command prompt to send commands to the device.
 */

const { WebSocketServer } = require('ws');
const readline = require('readline');
const crypto = require('crypto');

const PORT = 8080;
const wss = new WebSocketServer({ port: PORT, path: '/ws' });

let deviceSocket = null;
let pendingCommands = new Map();

const HELP = `
Commands:
  info              — Get device info
  state             — Get device state
  containers        — List containers
  start <id>        — Start container
  stop <id>         — Stop container
  restart <id>      — Restart container
  remove <id>       — Remove container
  logs <id> [tail]  — Get container logs
  update <id> <img> — Trigger update
  update-status     — Get update status
  raw <json>        — Send raw JSON message
  help              — Show this help
  quit              — Exit
`;

function sendCommand(action, payload = {}) {
  if (!deviceSocket) {
    console.log('[!] No device connected');
    return;
  }
  const id = crypto.randomUUID();
  const msg = { type: 'command', action, id, payload };
  deviceSocket.send(JSON.stringify(msg));
  pendingCommands.set(id, { action, sent: Date.now() });
  console.log(`[>] Sent ${action} (id: ${id.slice(0, 8)}...)`);
}

wss.on('connection', (ws) => {
  console.log('[+] Device connected');
  deviceSocket = ws;

  ws.on('message', (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch (_err) {
      console.log('[?] Non-JSON message:', data.toString().slice(0, 100));
      return;
    }

    switch (msg.type) {
      case 'auth': {
        console.log(`[A] Auth received — device_id: ${msg.payload?.device_id}, hostname: ${msg.payload?.hostname}`);
        // Acknowledge auth
        ws.send(JSON.stringify({
          type: 'response',
          id: msg.id,
          success: true,
          payload: { auth: true },
        }));
        console.log('[A] Auth acknowledged');
        break;
      }
      case 'telemetry': {
        const p = msg.payload || {};
        const cpu = p.cpu?.usage?.toFixed(1) ?? '?';
        const mem = p.memory?.usedPercent?.toFixed(1) ?? '?';
        const disk = p.disk?.usedPercent?.toFixed(1) ?? '?';
        console.log(`[T] Telemetry — CPU: ${cpu}%  MEM: ${mem}%  DISK: ${disk}%`);
        break;
      }
      case 'heartbeat': {
        const uptime = msg.payload?.uptime?.toFixed(0) ?? '?';
        console.log(`[H] Heartbeat — uptime: ${uptime}s`);
        break;
      }
      case 'response': {
        const pending = pendingCommands.get(msg.id);
        const action = pending?.action || 'unknown';
        pendingCommands.delete(msg.id);
        if (msg.success) {
          console.log(`[<] Response OK (${action}):`);
          console.log(JSON.stringify(msg.payload, null, 2));
        } else {
          console.log(`[<] Response ERROR (${action}): ${msg.error}`);
        }
        break;
      }
      default:
        console.log(`[?] Unknown type: ${msg.type}`, JSON.stringify(msg).slice(0, 200));
    }
  });

  ws.on('close', (code, reason) => {
    console.log(`[-] Device disconnected (code: ${code}, reason: ${reason})`);
    deviceSocket = null;
  });

  ws.on('pong', () => {
    // Device responded to our ping
  });
});

console.log(`Mock cloud server listening on ws://localhost:${PORT}/ws`);
console.log('Waiting for device to connect...');
console.log(`Set WS_ENDPOINT=ws://localhost:${PORT}/ws when running the supervisor`);
console.log(HELP);

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, prompt: 'cloud> ' });
rl.prompt();

rl.on('line', (line) => {
  const parts = line.trim().split(/\s+/);
  const cmd = parts[0];

  switch (cmd) {
    case 'info':
      sendCommand('device.info');
      break;
    case 'state':
      sendCommand('device.state');
      break;
    case 'containers':
      sendCommand('container.list');
      break;
    case 'start':
      sendCommand('container.start', { id: parts[1] });
      break;
    case 'stop':
      sendCommand('container.stop', { id: parts[1] });
      break;
    case 'restart':
      sendCommand('container.restart', { id: parts[1] });
      break;
    case 'remove':
      sendCommand('container.remove', { id: parts[1] });
      break;
    case 'logs':
      sendCommand('container.logs', { id: parts[1], tail: parseInt(parts[2], 10) || 100 });
      break;
    case 'update':
      sendCommand('update.trigger', { containerId: parts[1], image: parts[2] });
      break;
    case 'update-status':
      sendCommand('update.status');
      break;
    case 'raw':
      if (deviceSocket) {
        deviceSocket.send(parts.slice(1).join(' '));
        console.log('[>] Sent raw message');
      }
      break;
    case 'help':
      console.log(HELP);
      break;
    case 'quit':
    case 'exit':
      process.exit(0);
      break;
    case '':
      break;
    default:
      console.log(`Unknown command: ${cmd}. Type "help" for usage.`);
  }

  rl.prompt();
});

rl.on('close', () => {
  process.exit(0);
});
