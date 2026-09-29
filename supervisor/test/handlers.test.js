'use strict';

jest.mock('dockerode', () => require('./helpers/dockerode-mock').dockerodeMockFactory());

jest.mock('ws', () => require('./helpers/ws-mock').wsMockFactory());

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

// Never let reboot/shutdown tests reach the real `sudo systemctl`.
jest.mock('child_process', () => ({
  ...jest.requireActual('child_process'),
  execFile: jest.fn(),
}));

const { execFile } = require('child_process');
const containerManager = require('../src/services/container-manager');
const updateManager = require('../src/services/update-manager');
const stateManager = require('../src/services/state-manager');
const monitor = require('../src/services/monitor');
const connection = require('../src/ws/connection');
const securityManager = require('../src/services/security-manager');
const { handleMessage, handleCommand, COMMAND_MAP, _resetRateLimit } = require('../src/ws/handlers');

describe('handlers', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    jest.spyOn(containerManager, 'listContainers').mockResolvedValue([]);
    jest.spyOn(containerManager, 'startContainer').mockResolvedValue();
    jest.spyOn(containerManager, 'stopContainer').mockResolvedValue();
    jest.spyOn(containerManager, 'restartContainer').mockResolvedValue();
    jest.spyOn(containerManager, 'removeContainer').mockResolvedValue();
    jest.spyOn(containerManager, 'getLogs').mockResolvedValue('');

    jest.spyOn(updateManager, 'triggerUpdate').mockResolvedValue();
    jest.spyOn(updateManager, 'getUpdateStatus').mockReturnValue({
      state: 'idle', error: null, progress: null,
    });

    jest.spyOn(stateManager, 'load').mockResolvedValue({});

    jest.spyOn(monitor, 'getLastMetrics').mockReturnValue(null);
    jest.spyOn(monitor, 'collectMetrics').mockResolvedValue({});
    jest.spyOn(monitor, 'checkThresholds').mockReturnValue([]);

    jest.spyOn(connection, 'send').mockReturnValue(true);
    jest.spyOn(connection, 'isAuthenticated').mockReturnValue(true);
    jest.spyOn(connection, 'setAuthenticated').mockImplementation(() => {});
    jest.spyOn(connection, 'getPendingAuthId').mockReturnValue(null);

    _resetRateLimit();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('handleMessage', () => {
    it('ignores non-JSON messages', () => {
      handleMessage('not json');
      expect(connection.send).not.toHaveBeenCalled();
    });

    it('rejects invalid messages and sends error if id present', () => {
      handleMessage(JSON.stringify({ type: 'invalid', id: 'x' }));
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'response', id: 'x', success: false }),
      );
    });

    it('ignores invalid messages without id', () => {
      handleMessage(JSON.stringify({ type: 'invalid' }));
      expect(connection.send).not.toHaveBeenCalled();
    });

    it('routes command messages to handleCommand when authenticated', async () => {
      containerManager.listContainers.mockResolvedValue([]);
      handleMessage(JSON.stringify({
        type: 'command',
        action: 'container.list',
        id: 'cmd-1',
      }));

      await new Promise((r) => setTimeout(r, 10));
      expect(containerManager.listContainers).toHaveBeenCalled();
    });

    it('rejects commands when not authenticated', () => {
      connection.isAuthenticated.mockReturnValue(false);
      handleMessage(JSON.stringify({
        type: 'command',
        action: 'container.list',
        id: 'cmd-2',
      }));

      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'response',
          id: 'cmd-2',
          success: false,
          error: 'Not authenticated',
        }),
      );
      expect(containerManager.listContainers).not.toHaveBeenCalled();
    });

    it('handles auth acknowledgment from server', () => {
      jest.spyOn(connection, 'clearPendingAuthId').mockImplementation(() => {});
      connection.getPendingAuthId.mockReturnValue('auth-1');
      handleMessage(JSON.stringify({
        type: 'response',
        id: 'auth-1',
        success: true,
        payload: { auth: true },
      }));

      expect(connection.setAuthenticated).toHaveBeenCalledWith(true);
      expect(connection.clearPendingAuthId).toHaveBeenCalled();
    });

    it('ignores non-command valid message types', () => {
      handleMessage(JSON.stringify({ type: 'heartbeat' }));
      expect(connection.send).not.toHaveBeenCalled();
    });
  });

  describe('handleCommand', () => {
    it('sends error for unknown action', async () => {
      await handleCommand({ action: 'unknown.action', id: 'x', payload: {} });
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'response',
          id: 'x',
          success: false,
          error: expect.stringContaining('Unknown action'),
        }),
      );
    });

    it('sends sanitized error when handler throws', async () => {
      containerManager.listContainers.mockRejectedValue(new Error('docker down'));
      await handleCommand({ action: 'container.list', id: 'x', payload: {} });
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'response',
          id: 'x',
          success: false,
          error: 'Command container.list failed',
        }),
      );
    });
  });

  describe('device commands', () => {
    it('device.info returns host info with metrics', async () => {
      monitor.getLastMetrics.mockReturnValue({ cpu: { usage: 42 } });
      await handleCommand({ action: 'device.info', id: '1', payload: {} });

      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'response',
          id: '1',
          success: true,
          payload: expect.objectContaining({
            hostname: expect.any(String),
            platform: expect.any(String),
            arch: expect.any(String),
            uptime: expect.any(Number),
          }),
        }),
      );
    });

    it('device.state returns state from stateManager', async () => {
      const mockState = { boot_count: 5 };
      stateManager.load.mockResolvedValue(mockState);
      await handleCommand({ action: 'device.state', id: '2', payload: {} });

      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          payload: mockState,
          success: true,
        }),
      );
    });

    describe.each([
      ['device.reboot', 'Reboot initiated', 'reboot', 'Reboot failed'],
      ['device.shutdown', 'Shutdown initiated', 'poweroff', 'Shutdown failed'],
    ])('%s', (action, status, systemctlVerb, failureMessage) => {
      beforeEach(() => jest.useFakeTimers());
      afterEach(() => jest.useRealTimers());

      it('responds immediately and runs systemctl after a delay', async () => {
        await handleCommand({ action, id: '3', payload: {} });
        expect(connection.send).toHaveBeenCalledWith(
          expect.objectContaining({ payload: { status }, success: true }),
        );
        expect(execFile).not.toHaveBeenCalled();

        jest.advanceTimersByTime(1000);
        expect(execFile).toHaveBeenCalledWith(
          'sudo', ['systemctl', systemctlVerb], expect.any(Function),
        );
      });

      it('logs when systemctl fails', async () => {
        const logger = require('../src/utils/logger');
        await handleCommand({ action, id: '4', payload: {} });
        jest.advanceTimersByTime(1000);

        const callback = execFile.mock.calls[0][2];
        callback(new Error('denied'));
        expect(logger.error).toHaveBeenCalledWith({ err: 'denied' }, failureMessage);
      });
    });
  });

  describe('container commands', () => {
    it('container.list returns container list', async () => {
      const containers = [{ id: 'c1', name: 'app' }];
      containerManager.listContainers.mockResolvedValue(containers);
      await handleCommand({ action: 'container.list', id: '5', payload: {} });

      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ payload: containers, success: true }),
      );
    });

    it('container.start starts the specified container', async () => {
      containerManager.startContainer.mockResolvedValue();
      await handleCommand({ action: 'container.start', id: '6', payload: { id: 'c1' } });

      expect(containerManager.startContainer).toHaveBeenCalledWith('c1');
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          payload: { status: 'started', id: 'c1' },
          success: true,
        }),
      );
    });

    it('container.start rejects missing id', async () => {
      await handleCommand({ action: 'container.start', id: '6b', payload: {} });
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ success: false, error: 'Command container.start failed' }),
      );
    });

    it('container.stop stops the specified container', async () => {
      containerManager.stopContainer.mockResolvedValue();
      await handleCommand({ action: 'container.stop', id: '7', payload: { id: 'c1' } });

      expect(containerManager.stopContainer).toHaveBeenCalledWith('c1');
    });

    it('container.restart restarts the specified container', async () => {
      containerManager.restartContainer.mockResolvedValue();
      await handleCommand({ action: 'container.restart', id: '8', payload: { id: 'c1' } });

      expect(containerManager.restartContainer).toHaveBeenCalledWith('c1');
    });

    it('container.remove removes with force', async () => {
      containerManager.removeContainer.mockResolvedValue();
      await handleCommand({ action: 'container.remove', id: '9', payload: { id: 'c1' } });

      expect(containerManager.removeContainer).toHaveBeenCalledWith('c1', true);
    });

    it('container.logs returns logs with default tail', async () => {
      containerManager.getLogs.mockResolvedValue('line 1\nline 2');
      await handleCommand({ action: 'container.logs', id: '10', payload: { id: 'c1' } });

      expect(containerManager.getLogs).toHaveBeenCalledWith('c1', 100);
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          payload: { logs: 'line 1\nline 2' },
          success: true,
        }),
      );
    });

    it('container.logs respects custom tail', async () => {
      containerManager.getLogs.mockResolvedValue('line');
      await handleCommand({
        action: 'container.logs',
        id: '11',
        payload: { id: 'c1', tail: 50 },
      });
      expect(containerManager.getLogs).toHaveBeenCalledWith('c1', 50);
    });

    it('container.logs caps tail at 10000', async () => {
      containerManager.getLogs.mockResolvedValue('line');
      await handleCommand({
        action: 'container.logs',
        id: '11b',
        payload: { id: 'c1', tail: 99999 },
      });
      expect(containerManager.getLogs).toHaveBeenCalledWith('c1', 10000);
    });

    it('container.logs defaults tail=0 to 100', async () => {
      containerManager.getLogs.mockResolvedValue('line');
      await handleCommand({
        action: 'container.logs',
        id: '11c',
        payload: { id: 'c1', tail: 0 },
      });
      expect(containerManager.getLogs).toHaveBeenCalledWith('c1', 100);
    });
  });

  describe('update commands', () => {
    it('update.trigger calls triggerUpdate', async () => {
      updateManager.triggerUpdate.mockResolvedValue();
      await handleCommand({
        action: 'update.trigger',
        id: '12',
        payload: { containerId: 'c1', image: 'app:2.0' },
      });

      expect(updateManager.triggerUpdate).toHaveBeenCalledWith('c1', 'app:2.0');
    });

    it('update.trigger rejects missing containerId', async () => {
      await handleCommand({
        action: 'update.trigger',
        id: '12b',
        payload: { image: 'app:2.0' },
      });
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ success: false, error: 'Command update.trigger failed' }),
      );
    });

    it('update.trigger rejects missing image', async () => {
      await handleCommand({
        action: 'update.trigger',
        id: '12c',
        payload: { containerId: 'c1' },
      });
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ success: false, error: 'Command update.trigger failed' }),
      );
    });

    it('update.trigger rejects disallowed image', async () => {
      jest.spyOn(securityManager, 'validateImage').mockReturnValue({
        valid: false, reason: 'Registry not allowed',
      });
      await handleCommand({
        action: 'update.trigger',
        id: '12d',
        payload: { containerId: 'c1', image: 'evil.io/malware:latest' },
      });
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ success: false, error: 'Command update.trigger failed' }),
      );
      expect(updateManager.triggerUpdate).not.toHaveBeenCalled();
    });

    it('update.status returns update status', async () => {
      const status = { state: 'idle', error: null, progress: null };
      updateManager.getUpdateStatus.mockReturnValue(status);
      await handleCommand({ action: 'update.status', id: '13', payload: {} });

      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ payload: status, success: true }),
      );
    });
  });

  describe('COMMAND_MAP', () => {
    it('maps all 12 expected actions', () => {
      const expectedActions = [
        'device.info', 'device.state', 'device.reboot', 'device.shutdown',
        'container.list', 'container.start', 'container.stop', 'container.restart',
        'container.remove', 'container.logs', 'update.trigger', 'update.status',
      ];
      for (const action of expectedActions) {
        expect(action in COMMAND_MAP).toBe(true);
        expect(typeof COMMAND_MAP[action]).toBe('function');
      }
    });
  });

  describe('rate limiting', () => {
    it('allows commands within rate limit', async () => {
      await handleCommand({ action: 'container.list', id: 'r1', payload: {} });
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({ success: true }),
      );
    });

    it('rejects commands after 60 per minute', async () => {
      for (let i = 0; i < 60; i++) {
        await handleCommand({ action: 'container.list', id: `r${i}`, payload: {} });
      }
      await handleCommand({ action: 'container.list', id: 'r-over', payload: {} });
      const lastCall = connection.send.mock.calls[connection.send.mock.calls.length - 1][0];
      expect(lastCall.success).toBe(false);
      expect(lastCall.error).toContain('Rate limit');
    });

    it('resets rate limit via _resetRateLimit', async () => {
      for (let i = 0; i < 60; i++) {
        await handleCommand({ action: 'container.list', id: `r${i}`, payload: {} });
      }
      _resetRateLimit();
      await handleCommand({ action: 'container.list', id: 'after-reset', payload: {} });
      const lastCall = connection.send.mock.calls[connection.send.mock.calls.length - 1][0];
      expect(lastCall.success).toBe(true);
    });
  });

  describe('auth ID tracking', () => {
    beforeEach(() => {
      jest.spyOn(connection, 'clearPendingAuthId').mockImplementation(() => {});
    });

    it('accepts auth ack when pendingAuthId matches', () => {
      connection.getPendingAuthId.mockReturnValue('auth-123');
      handleMessage(JSON.stringify({
        type: 'response',
        id: 'auth-123',
        success: true,
        payload: { auth: true },
      }));
      expect(connection.setAuthenticated).toHaveBeenCalledWith(true);
      expect(connection.clearPendingAuthId).toHaveBeenCalled();
    });

    it('rejects auth ack when pendingAuthId does not match', () => {
      connection.getPendingAuthId.mockReturnValue('auth-123');
      handleMessage(JSON.stringify({
        type: 'response',
        id: 'wrong-id',
        success: true,
        payload: { auth: true },
      }));
      expect(connection.setAuthenticated).not.toHaveBeenCalled();
    });

    it('rejects auth ack when no pendingAuthId is set', () => {
      connection.getPendingAuthId.mockReturnValue(null);
      handleMessage(JSON.stringify({
        type: 'response',
        id: 'any-id',
        success: true,
        payload: { auth: true },
      }));
      expect(connection.setAuthenticated).not.toHaveBeenCalled();
    });
  });
});
