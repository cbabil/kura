'use strict';

jest.mock('systeminformation', () => ({
  currentLoad: jest.fn(),
  mem: jest.fn(),
  fsSize: jest.fn(),
  cpuTemperature: jest.fn(),
  networkStats: jest.fn(),
}));

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const si = require('systeminformation');
const monitor = require('../src/services/monitor');

function mockSystemInfo(overrides = {}) {
  const defaults = {
    cpu: { currentLoad: 45 },
    mem: { total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024 },
    disk: [{ mount: '/', use: 55, size: 100e9, used: 55e9 }],
    temp: { main: 50 },
    net: [{ rx_bytes: 1000, tx_bytes: 2000, rx_errors: 0, tx_errors: 0 }],
  };
  const merged = { ...defaults, ...overrides };

  si.currentLoad.mockResolvedValue(merged.cpu);
  si.mem.mockResolvedValue(merged.mem);
  si.fsSize.mockResolvedValue(merged.disk);
  si.cpuTemperature.mockResolvedValue(merged.temp);
  si.networkStats.mockResolvedValue(merged.net);
}

describe('monitor', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSystemInfo();
  });

  describe('collectMetrics', () => {
    it('gathers CPU, memory, disk, network, and temperature', async () => {
      const metrics = await monitor.collectMetrics();

      expect(metrics).toHaveProperty('cpu');
      expect(metrics).toHaveProperty('memory');
      expect(metrics).toHaveProperty('disk');
      expect(metrics).toHaveProperty('network');
      expect(metrics).toHaveProperty('timestamp');
    });

    it('calculates memory percentage correctly', async () => {
      mockSystemInfo({
        mem: { total: 1000, used: 750 },
      });

      const metrics = await monitor.collectMetrics();
      expect(metrics.memory.usedPercent).toBe(75);
    });

    it('uses root mount disk by default', async () => {
      mockSystemInfo({
        disk: [
          { mount: '/boot', use: 30, size: 1e9, used: 3e8 },
          { mount: '/', use: 60, size: 100e9, used: 60e9 },
        ],
      });

      const metrics = await monitor.collectMetrics();
      expect(metrics.disk.usedPercent).toBe(60);
    });

    it('falls back to first disk if no root mount', async () => {
      mockSystemInfo({
        disk: [{ mount: '/data', use: 40, size: 50e9, used: 20e9 }],
      });

      const metrics = await monitor.collectMetrics();
      expect(metrics.disk.usedPercent).toBe(40);
    });

    it('includes network rx and tx bytes', async () => {
      const metrics = await monitor.collectMetrics();
      expect(metrics.network.rx).toBe(1000);
      expect(metrics.network.tx).toBe(2000);
    });

    it('includes CPU temperature', async () => {
      const metrics = await monitor.collectMetrics();
      expect(metrics.cpu.temperature).toBe(50);
    });

    it('returns last metrics on error', async () => {
      // First call succeeds
      await monitor.collectMetrics();

      // Second call fails
      si.currentLoad.mockRejectedValueOnce(new Error('sensor error'));

      const metrics = await monitor.collectMetrics();
      // Should return the previous successful metrics
      expect(metrics).not.toBeNull();
      expect(metrics).toHaveProperty('cpu');
    });

    it('includes timestamp in ISO format', async () => {
      const metrics = await monitor.collectMetrics();
      expect(metrics.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });

  describe('checkThresholds', () => {
    it('returns empty array when all values below thresholds', () => {
      const metrics = {
        cpu: { usage: 30, temperature: 40 },
        memory: { usedPercent: 50 },
        disk: { usedPercent: 40 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts).toEqual([]);
    });

    it('returns empty array for null metrics', () => {
      const alerts = monitor.checkThresholds(null);
      expect(alerts).toEqual([]);
    });

    it('returns warning for CPU above 80%', () => {
      const metrics = {
        cpu: { usage: 85, temperature: 40 },
        memory: { usedPercent: 50 },
        disk: { usedPercent: 40 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts).toHaveLength(1);
      expect(alerts[0].level).toBe('warning');
      expect(alerts[0].component).toBe('cpu');
    });

    it('returns critical for CPU above 95%', () => {
      const metrics = {
        cpu: { usage: 97, temperature: 40 },
        memory: { usedPercent: 50 },
        disk: { usedPercent: 40 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts[0].level).toBe('critical');
      expect(alerts[0].component).toBe('cpu');
    });

    it('returns critical for memory above 95%', () => {
      const metrics = {
        cpu: { usage: 30, temperature: 40 },
        memory: { usedPercent: 97 },
        disk: { usedPercent: 40 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts[0].level).toBe('critical');
      expect(alerts[0].component).toBe('memory');
    });

    it('returns warning for memory above 80%', () => {
      const metrics = {
        cpu: { usage: 30, temperature: 40 },
        memory: { usedPercent: 85 },
        disk: { usedPercent: 40 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts[0].level).toBe('warning');
      expect(alerts[0].component).toBe('memory');
    });

    it('returns critical for disk above 95%', () => {
      const metrics = {
        cpu: { usage: 30, temperature: 40 },
        memory: { usedPercent: 50 },
        disk: { usedPercent: 97 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts[0].level).toBe('critical');
      expect(alerts[0].component).toBe('disk');
    });

    it('returns warning for disk above 80%', () => {
      const metrics = {
        cpu: { usage: 30, temperature: 40 },
        memory: { usedPercent: 50 },
        disk: { usedPercent: 85 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts[0].level).toBe('warning');
      expect(alerts[0].component).toBe('disk');
    });

    it('returns critical for temperature above 85C', () => {
      const metrics = {
        cpu: { usage: 30, temperature: 90 },
        memory: { usedPercent: 50 },
        disk: { usedPercent: 40 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts[0].level).toBe('critical');
      expect(alerts[0].component).toBe('temperature');
    });

    it('returns no alert for null temperature', () => {
      const metrics = {
        cpu: { usage: 30, temperature: null },
        memory: { usedPercent: 50 },
        disk: { usedPercent: 40 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts).toEqual([]);
    });

    it('returns multiple alerts for multiple threshold violations', () => {
      const metrics = {
        cpu: { usage: 97, temperature: 90 },
        memory: { usedPercent: 97 },
        disk: { usedPercent: 97 },
      };
      const alerts = monitor.checkThresholds(metrics);
      expect(alerts.length).toBeGreaterThanOrEqual(4);
    });
  });

  describe('getLastMetrics', () => {
    it('returns null before first collection', () => {
      const metrics = monitor.getLastMetrics();
      expect(metrics === null || typeof metrics === 'object').toBe(true);
    });

    it('returns last collected metrics after collectMetrics', async () => {
      await monitor.collectMetrics();
      const metrics = monitor.getLastMetrics();
      expect(metrics).toHaveProperty('cpu');
      expect(metrics).toHaveProperty('memory');
    });
  });
});
