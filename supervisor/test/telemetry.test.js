'use strict';

jest.mock('ws', () => require('./helpers/ws-mock').wsMockFactory());

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const mockStop = jest.fn();
const mockSchedule = jest.fn().mockReturnValue({ stop: mockStop });
jest.mock('node-cron', () => ({
  schedule: mockSchedule,
}));

const monitor = require('../src/services/monitor');
const connection = require('../src/ws/connection');
const telemetry = require('../src/ws/telemetry');

describe('telemetry', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    jest.spyOn(monitor, 'collectMetrics').mockResolvedValue({});
    jest.spyOn(monitor, 'checkThresholds').mockReturnValue([]);
    jest.spyOn(connection, 'send').mockReturnValue(true);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('start', () => {
    it('schedules a cron task with the given expression', () => {
      telemetry.start('*/30 * * * * *');
      expect(mockSchedule).toHaveBeenCalledWith('*/30 * * * * *', expect.any(Function));
    });

    it('cron callback collects metrics and sends telemetry', async () => {
      const mockMetrics = { cpu: { usage: 42 } };
      monitor.collectMetrics.mockResolvedValue(mockMetrics);
      monitor.checkThresholds.mockReturnValue([]);

      telemetry.start();
      const cronCallback = mockSchedule.mock.calls[0][1];
      await cronCallback();

      expect(monitor.collectMetrics).toHaveBeenCalled();
      expect(monitor.checkThresholds).toHaveBeenCalledWith(mockMetrics);
      expect(connection.send).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'telemetry',
          payload: mockMetrics,
        }),
      );
    });

    it('handles errors in cron callback gracefully', async () => {
      monitor.collectMetrics.mockRejectedValue(new Error('sensor fail'));

      telemetry.start();
      const cronCallback = mockSchedule.mock.calls[0][1];
      await cronCallback();

      // Should not throw, just log
      expect(connection.send).not.toHaveBeenCalled();
    });
  });

  describe('stop', () => {
    it('stops the cron task', () => {
      mockSchedule.mockReturnValueOnce({ stop: mockStop });

      telemetry.start();
      telemetry.stop();
      expect(mockStop).toHaveBeenCalled();
    });

    it('handles stop when not started', () => {
      // Should not throw
      telemetry.stop();
    });
  });
});
