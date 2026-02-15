'use strict';

const si = require('systeminformation');
const logger = require('../utils/logger');
const { THRESHOLDS } = require('../utils/constants');

let lastMetrics = null;

async function collectMetrics() {
  try {
    const [cpu, mem, disk, temp, net] = await Promise.all([
      si.currentLoad(),
      si.mem(),
      si.fsSize(),
      si.cpuTemperature(),
      si.networkStats(),
    ]);

    const memPercent = (mem.used / mem.total) * 100;
    const rootDisk = disk.find((d) => d.mount === '/') || disk[0] || {};
    const diskPercent = rootDisk.use || 0;

    const primaryNet = net[0] || {};

    lastMetrics = {
      timestamp: new Date().toISOString(),
      cpu: { usage: cpu.currentLoad, temperature: temp.main },
      memory: { usedPercent: memPercent, total: mem.total, used: mem.used },
      disk: { usedPercent: diskPercent, total: rootDisk.size, used: rootDisk.used },
      network: { rx: primaryNet.rx_bytes, tx: primaryNet.tx_bytes },
    };

    return lastMetrics;
  } catch (err) {
    logger.error({ err: err.message }, 'Metrics collection failed');
    return lastMetrics;
  }
}

function checkThresholds(metrics) {
  if (!metrics) { return []; }
  const alerts = [];

  if (metrics.cpu.usage > THRESHOLDS.CPU_CRITICAL) {
    alerts.push({ level: 'critical', component: 'cpu', message: `CPU usage: ${metrics.cpu.usage.toFixed(1)}%` });
  } else if (metrics.cpu.usage > THRESHOLDS.CPU_WARNING) {
    alerts.push({ level: 'warning', component: 'cpu', message: `CPU usage: ${metrics.cpu.usage.toFixed(1)}%` });
  }

  if (metrics.memory.usedPercent > THRESHOLDS.MEMORY_CRITICAL) {
    alerts.push({ level: 'critical', component: 'memory', message: `Memory: ${metrics.memory.usedPercent.toFixed(1)}%` });
  } else if (metrics.memory.usedPercent > THRESHOLDS.MEMORY_WARNING) {
    alerts.push({ level: 'warning', component: 'memory', message: `Memory: ${metrics.memory.usedPercent.toFixed(1)}%` });
  }

  if (metrics.disk.usedPercent > THRESHOLDS.DISK_CRITICAL) {
    alerts.push({ level: 'critical', component: 'disk', message: `Disk: ${metrics.disk.usedPercent.toFixed(1)}%` });
  } else if (metrics.disk.usedPercent > THRESHOLDS.DISK_WARNING) {
    alerts.push({ level: 'warning', component: 'disk', message: `Disk: ${metrics.disk.usedPercent.toFixed(1)}%` });
  }

  if (metrics.cpu.temperature && metrics.cpu.temperature > THRESHOLDS.TEMP_CRITICAL) {
    alerts.push({ level: 'critical', component: 'temperature', message: `CPU temp: ${metrics.cpu.temperature}C` });
  }

  for (const alert of alerts) {
    logger.warn({ alert }, 'Threshold alert triggered');
  }

  return alerts;
}

function getLastMetrics() {
  return lastMetrics;
}

module.exports = {
  collectMetrics,
  checkThresholds,
  getLastMetrics,
};
