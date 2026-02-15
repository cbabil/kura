'use strict';

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const protocol = require('../src/ws/protocol');

describe('protocol', () => {
  describe('createAuth', () => {
    it('returns auth message with type and payload', () => {
      const msg = protocol.createAuth();
      expect(msg.type).toBe('auth');
      expect(msg.id).toBeDefined();
      expect(msg.payload).toHaveProperty('device_id');
      expect(msg.payload).toHaveProperty('api_key');
      expect(msg.payload).toHaveProperty('hostname');
      expect(msg.payload).toHaveProperty('platform');
      expect(msg.payload).toHaveProperty('arch');
    });

    it('generates unique ids', () => {
      const a = protocol.createAuth();
      const b = protocol.createAuth();
      expect(a.id).not.toBe(b.id);
    });
  });

  describe('createResponse', () => {
    it('returns success response with matching id', () => {
      const msg = protocol.createResponse('req-1', { data: 'ok' });
      expect(msg).toEqual({
        type: 'response',
        id: 'req-1',
        success: true,
        payload: { data: 'ok' },
      });
    });
  });

  describe('createError', () => {
    it('returns error response from Error object', () => {
      const msg = protocol.createError('req-2', new Error('boom'));
      expect(msg).toEqual({
        type: 'response',
        id: 'req-2',
        success: false,
        error: 'boom',
      });
    });

    it('returns error response from string', () => {
      const msg = protocol.createError('req-3', 'bad request');
      expect(msg).toEqual({
        type: 'response',
        id: 'req-3',
        success: false,
        error: 'bad request',
      });
    });
  });

  describe('createTelemetry', () => {
    it('wraps metrics in telemetry envelope', () => {
      const metrics = { cpu: { usage: 42 } };
      const msg = protocol.createTelemetry(metrics);
      expect(msg.type).toBe('telemetry');
      expect(msg.id).toBeDefined();
      expect(msg.payload).toEqual(metrics);
    });
  });

  describe('createHeartbeat', () => {
    it('returns heartbeat with uptime', () => {
      const msg = protocol.createHeartbeat();
      expect(msg.type).toBe('heartbeat');
      expect(msg.id).toBeDefined();
      expect(msg.payload).toHaveProperty('uptime');
      expect(typeof msg.payload.uptime).toBe('number');
    });
  });

  describe('validateInbound', () => {
    it('rejects non-object messages', () => {
      expect(protocol.validateInbound(null)).toEqual({
        valid: false,
        error: 'Message must be a JSON object',
      });
      expect(protocol.validateInbound('string')).toEqual({
        valid: false,
        error: 'Message must be a JSON object',
      });
    });

    it('rejects arrays', () => {
      expect(protocol.validateInbound([1, 2])).toEqual({
        valid: false,
        error: 'Message must be a JSON object',
      });
    });

    it('rejects messages with invalid type', () => {
      const result = protocol.validateInbound({ type: 'invalid' });
      expect(result.valid).toBe(false);
      expect(result.error).toContain('Invalid message type');
    });

    it('rejects command messages without action', () => {
      const result = protocol.validateInbound({ type: 'command', id: '1' });
      expect(result.valid).toBe(false);
      expect(result.error).toContain('action');
    });

    it('rejects command messages without id', () => {
      const result = protocol.validateInbound({ type: 'command', action: 'test' });
      expect(result.valid).toBe(false);
      expect(result.error).toContain('id');
    });

    it('accepts valid command messages', () => {
      const result = protocol.validateInbound({
        type: 'command',
        action: 'device.info',
        id: '123',
      });
      expect(result).toEqual({ valid: true });
    });

    it('accepts valid heartbeat messages', () => {
      const result = protocol.validateInbound({ type: 'heartbeat' });
      expect(result).toEqual({ valid: true });
    });

    it('accepts all valid message types', () => {
      for (const type of protocol.VALID_TYPES) {
        if (type === 'command') continue;
        const result = protocol.validateInbound({ type });
        expect(result.valid).toBe(true);
      }
    });
  });
});
