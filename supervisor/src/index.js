'use strict';

const express = require('express');
const cron = require('node-cron');
const logger = require('./utils/logger');
const { DEFAULTS } = require('./utils/constants');
const { loadConfig } = require('./config');
const { createAuthMiddleware } = require('./middleware/auth');
const { errorHandler } = require('./middleware/error-handler');
const deviceRoutes = require('./routes/device');
const containerRoutes = require('./routes/containers');
const updateRoutes = require('./routes/updates');
const healthRoutes = require('./routes/health');
const metricsRoutes = require('./routes/metrics');
const monitor = require('./services/monitor');
const stateManager = require('./services/state-manager');
const provisioningManager = require('./services/provisioning-manager');

const config = loadConfig();
const app = express();
const port = config.network?.api_port || DEFAULTS.PORT;

app.use(express.json());
app.use(createAuthMiddleware(config));

app.use('/v1', healthRoutes);
app.use('/v1', metricsRoutes);
app.use('/v1', deviceRoutes);
app.use('/v1', containerRoutes);
app.use('/v1', updateRoutes);

app.use(errorHandler);

let server = null;
let monitorTask = null;

async function start() {
  logger.info('StraturaOS Supervisor starting');

  await stateManager.updateBootCount();

  const provisioned = await provisioningManager.isProvisioned();
  if (!provisioned) {
    logger.info('Device not provisioned, running first-boot setup');
    await provisioningManager.provision(config);
  }

  monitorTask = cron.schedule(DEFAULTS.MONITOR_CRON, async () => {
    try {
      const metrics = await monitor.collectMetrics();
      monitor.checkThresholds(metrics);
    } catch (err) {
      logger.error({ err: err.message }, 'Monitor cycle failed');
    }
  });

  server = app.listen(port, () => {
    logger.info({ port }, 'Supervisor API listening');
  });

  return server;
}

async function shutdown() {
  logger.info('Supervisor shutting down');

  if (monitorTask) {
    monitorTask.stop();
    monitorTask = null;
  }

  if (server) {
    await new Promise((resolve) => { server.close(resolve); });
    server = null;
  }

  logger.info('Supervisor stopped');
}

function handleSignal(signal) {
  logger.info({ signal }, 'Received signal');
  shutdown().then(() => { process.exit(0); });
}

process.on('SIGTERM', () => handleSignal('SIGTERM'));
process.on('SIGINT', () => handleSignal('SIGINT'));

process.on('unhandledRejection', (err) => {
  logger.error({ err: err?.message || err }, 'Unhandled rejection');
});

process.on('uncaughtException', (err) => {
  logger.fatal({ err: err.message, stack: err.stack }, 'Uncaught exception');
  process.exit(1);
});

if (require.main === module) {
  start().catch((err) => {
    logger.fatal({ err: err.message }, 'Failed to start supervisor');
    process.exit(1);
  });
}

module.exports = { app, start, shutdown };
