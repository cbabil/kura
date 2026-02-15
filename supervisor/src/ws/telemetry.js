'use strict';

const cron = require('node-cron');
const logger = require('../utils/logger');
const monitor = require('../services/monitor');
const connection = require('./connection');
const { createTelemetry } = require('./protocol');

let telemetryTask = null;

function start(cronExpr = '*/30 * * * * *') {
  telemetryTask = cron.schedule(cronExpr, async () => {
    try {
      const metrics = await monitor.collectMetrics();
      monitor.checkThresholds(metrics);
      connection.send(createTelemetry(metrics));
    } catch (err) {
      logger.error({ err: err.message }, 'Telemetry cycle failed');
    }
  });
  logger.info({ cron: cronExpr }, 'Telemetry loop started');
}

function stop() {
  if (telemetryTask) {
    telemetryTask.stop();
    telemetryTask = null;
  }
}

module.exports = { start, stop };
