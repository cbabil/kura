'use strict';

const si = require('systeminformation');
const client = require('prom-client');
const logger = require('../utils/logger');
const { THRESHOLDS } = require('../utils/constants');

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const cpuUsage = new client.Gauge({ name: 'system_cpu_usage', help: 'CPU usage %', registers: [register] });
const memUsage = new client.Gauge({ name: 'system_memory_usage', help: 'Memory usage %', registers: [register] });
const diskUsage = new client.Gauge({ name: 'system_disk_usage', help: 'Disk usage %', registers: [register] });
const cpuTemp = new client.Gauge({ name: 'system_cpu_temperature', help: 'CPU temperature C', registers: [register] });
const netErrors = new client.Counter({ name: 'system_network_errors_total', help: 'Network errors', registers: [register] });

const containerStatus = new client.Gauge({
  name: 'container_status',
  help: 'Container status (1=running, 0=stopped)',
  labelNames: ['name'],
  registers: [register],
});

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

    cpuUsage.set(cpu.currentLoad || 0);
    memUsage.set(memPercent);
    diskUsage.set(diskPercent);

    if (temp.main !== null && temp.main !== undefined) {
      cpuTemp.set(temp.main);
    }

    const primaryNet = net[0] || {};
    if ((primaryNet.rx_errors || 0) > 0 || (primaryNet.tx_errors || 0) > 0) {
      netErrors.inc();
    }

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

function setContainerMetric(name, running) {
  containerStatus.set({ name }, running ? 1 : 0);
}

async function getPrometheusMetrics() {
  return register.metrics();
}

function getLastMetrics() {
  return lastMetrics;
}

module.exports = {
  collectMetrics,
  checkThresholds,
  getPrometheusMetrics,
  getLastMetrics,
  setContainerMetric,
};
