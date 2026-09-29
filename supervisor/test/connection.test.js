'use strict';

jest.mock('ws', () => require('./helpers/ws-mock').wsMockFactory());

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

describe('connection', () => {
  let connection;
  let mockWsInstance;
  let MockWebSocket;

  beforeEach(() => {
    jest.useFakeTimers();
    // Fresh registry so connection.js module state (ws, timers) never leaks
    // between tests; re-require the helper so we share the mock's references.
    jest.resetModules();
    ({ mockWsInstance, MockWebSocket } = require('./helpers/ws-mock'));
    connection = require('../src/ws/connection');

    mockWsInstance.readyState = MockWebSocket.OPEN;
    mockWsInstance.on.mockReset();
    mockWsInstance.send.mockReset();
    mockWsInstance.close.mockReset();
    mockWsInstance.terminate.mockReset();
    mockWsInstance.ping.mockReset();
    mockWsInstance.removeAllListeners.mockReset();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('connect', () => {
    it('creates a WebSocket connection', () => {
      connection.connect(jest.fn());
      expect(MockWebSocket).toHaveBeenCalled();
    });

    it('passes maxPayload option', () => {
      connection.connect(jest.fn());
      expect(MockWebSocket).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ maxPayload: 128 * 1024 }),
      );
    });

    it('registers event handlers on the WebSocket', () => {
      connection.connect(jest.fn());
      const events = mockWsInstance.on.mock.calls.map((c) => c[0]);
      expect(events).toContain('open');
      expect(events).toContain('message');
      expect(events).toContain('close');
      expect(events).toContain('error');
      expect(events).toContain('pong');
    });

    it('sends auth message on open', () => {
      connection.connect(jest.fn());
      const openHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'open')[1];
      openHandler();

      expect(mockWsInstance.send).toHaveBeenCalled();
      const sent = JSON.parse(mockWsInstance.send.mock.calls[0][0]);
      expect(sent.type).toBe('auth');
    });

    it('calls message handler on incoming message', () => {
      const handler = jest.fn();
      connection.connect(handler);
      const msgHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'message')[1];
      msgHandler(Buffer.from('{"type":"command"}'));
      expect(handler).toHaveBeenCalledWith('{"type":"command"}');
    });

    it('cleans up existing connection on reconnect', () => {
      connection.connect(jest.fn());
      // Second connect should clean up first
      connection.connect(jest.fn());
      expect(mockWsInstance.removeAllListeners).toHaveBeenCalled();
    });
  });

  describe('send', () => {
    it('sends JSON-serialized message when connected', () => {
      connection.connect(jest.fn());
      const result = connection.send({ type: 'test' });
      expect(result).toBe(true);
      expect(mockWsInstance.send).toHaveBeenCalledWith('{"type":"test"}');
    });

    it('returns false when not connected', () => {
      mockWsInstance.readyState = MockWebSocket.CLOSED;
      connection.connect(jest.fn());
      const result = connection.send({ type: 'test' });
      expect(result).toBe(false);
    });
  });

  describe('close', () => {
    it('closes the WebSocket connection', () => {
      connection.connect(jest.fn());
      connection.close();
      expect(mockWsInstance.close).toHaveBeenCalledWith(1000, 'Supervisor shutting down');
    });

    it('resets authenticated state on close', () => {
      connection.connect(jest.fn());
      connection.setAuthenticated(true);
      expect(connection.isAuthenticated()).toBe(true);
      connection.close();
      expect(connection.isAuthenticated()).toBe(false);
    });
  });

  describe('isConnected', () => {
    it('returns true when WebSocket is open', () => {
      connection.connect(jest.fn());
      expect(connection.isConnected()).toBe(true);
    });

    it('returns false before connect is called', () => {
      expect(connection.isConnected()).toBe(false);
    });
  });

  describe('isAuthenticated / setAuthenticated', () => {
    it('defaults to false', () => {
      expect(connection.isAuthenticated()).toBe(false);
    });

    it('can be set to true', () => {
      connection.setAuthenticated(true);
      expect(connection.isAuthenticated()).toBe(true);
    });

    it('resets to false on connect', () => {
      connection.setAuthenticated(true);
      connection.connect(jest.fn());
      expect(connection.isAuthenticated()).toBe(false);
    });
  });

  describe('reconnect on close', () => {
    it('schedules reconnect when connection closes', () => {
      connection.connect(jest.fn());
      const closeHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'close')[1];

      closeHandler(1006, Buffer.from('abnormal'));

      jest.advanceTimersByTime(2000);
      expect(MockWebSocket).toHaveBeenCalledTimes(2);
    });

    it('does not reconnect after explicit close', () => {
      connection.connect(jest.fn());
      connection.close();

      const closeHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'close')[1];
      closeHandler(1000, Buffer.from('normal'));

      jest.advanceTimersByTime(120000);
      expect(MockWebSocket).toHaveBeenCalledTimes(1);
    });

    it('resets authenticated on close event', () => {
      connection.connect(jest.fn());
      connection.setAuthenticated(true);

      const closeHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'close')[1];
      closeHandler(1006, Buffer.from('abnormal'));

      expect(connection.isAuthenticated()).toBe(false);
    });

    it('resets pendingAuthId on close event', () => {
      connection.connect(jest.fn());
      // Trigger open to set pendingAuthId
      const openHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'open')[1];
      openHandler();
      expect(connection.getPendingAuthId()).not.toBeNull();

      const closeHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'close')[1];
      closeHandler(1006, Buffer.from('abnormal'));

      expect(connection.getPendingAuthId()).toBeNull();
    });
  });

  describe('heartbeat', () => {
    it('sends ping on heartbeat interval after open', () => {
      connection.connect(jest.fn());
      const openHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'open')[1];
      openHandler();

      jest.advanceTimersByTime(30000);
      expect(mockWsInstance.ping).toHaveBeenCalled();
    });

    it('terminates connection on heartbeat timeout', () => {
      connection.connect(jest.fn());
      const openHandler = mockWsInstance.on.mock.calls.find((c) => c[0] === 'open')[1];
      openHandler();

      jest.advanceTimersByTime(90000);
      expect(mockWsInstance.terminate).toHaveBeenCalled();
    });
  });
});
