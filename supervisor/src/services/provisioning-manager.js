'use strict';

const logger = require('../utils/logger');
const stateManager = require('./state-manager');
const containerManager = require('./container-manager');
const securityManager = require('./security-manager');

async function isProvisioned() {
  const state = await stateManager.load();
  return state.provisioning.completed;
}

async function provision(config) {
  try {
    const provisioned = await isProvisioned();
    if (provisioned) {
      logger.info('Device already provisioned');
      return true;
    }

    logger.info('Starting device provisioning');

    await setupContainers(config.applications || []);

    await stateManager.setProvisioningComplete();
    logger.info('Device provisioning completed');
    return true;
  } catch (err) {
    logger.error({ err: err.message }, 'Device provisioning failed');
    return false;
  }
}

async function setupContainers(applications) {
  for (const app of applications) {
    if (!app.name || !app.image) {
      logger.warn({ app: app.name }, 'Skipping invalid app config');
      continue;
    }

    const validation = securityManager.validateImage(app.image);
    if (!validation.valid) {
      logger.error({ image: app.image, reason: validation.reason }, 'Image validation failed');
      continue;
    }

    try {
      logger.info({ image: app.image }, 'Pulling image');
      await containerManager.pullImage(app.image);

      logger.info({ name: app.name }, 'Creating container');
      await containerManager.createContainer(app);

      await stateManager.updateContainerStatus(app.name, {
        status: 'running',
        image: app.image,
        started_at: new Date().toISOString(),
      });
    } catch (err) {
      logger.error({ name: app.name, err: err.message }, 'Container setup failed');
      throw err;
    }
  }
}

module.exports = { isProvisioned, provision };
