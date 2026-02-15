'use strict';

const logger = require('./utils/logger');
const { DEFAULTS } = require('./utils/constants');
const brand = require('./utils/brand');
const { loadConfig } = require('./config');
const stateManager = require('./services/state-manager');
const provisioningManager = require('./services/provisioning-manager');
const { connect, close } = require('./ws/connection');
const { handleMessage } = require('./ws/handlers');
const telemetry = require('./ws/telemetry');

const config = loadConfig();

async function start() {
  logger.info(`${brand.BRAND_NAME} Supervisor starting`);

  await stateManager.updateBootCount();

  const provisioned = await provisioningManager.isProvisioned();
  if (!provisioned) {
    logger.info('Device not provisioned, running first-boot setup');
    await provisioningManager.provision(config);
  }

  connect(handleMessage);
  telemetry.start(DEFAULTS.TELEMETRY_CRON);

  logger.info('Supervisor started');
}

async function shutdown() {
  logger.info('Supervisor shutting down');
  telemetry.stop();
  close();
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

module.exports = { start, shutdown };
