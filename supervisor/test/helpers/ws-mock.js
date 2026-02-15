'use strict';

// Shared ws mock used by connection tests and any test that transitively
// loads connection.js (handlers, telemetry). Defined once so all files
// share the same references, avoiding cache vs mock ordering issues in Bun.

const mockWsInstance = {
  on: jest.fn(),
  send: jest.fn(),
  close: jest.fn(),
  terminate: jest.fn(),
  ping: jest.fn(),
  removeAllListeners: jest.fn(),
  readyState: 1,
};

const MockWebSocket = Object.assign(
  jest.fn().mockImplementation(() => mockWsInstance),
  { OPEN: 1, CLOSED: 3, CONNECTING: 0 },
);

const wsMockFactory = () => ({
  __esModule: true,
  default: MockWebSocket,
});

module.exports = { mockWsInstance, MockWebSocket, wsMockFactory };
