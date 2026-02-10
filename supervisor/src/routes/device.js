'use strict';

const { Router } = require('express');
const { execFile } = require('child_process');
const os = require('os');
const stateManager = require('../services/state-manager');
const monitor = require('../services/monitor');
const logger = require('../utils/logger');

const router = Router();

router.get('/device', async (_req, res, next) => {
  try {
    const metrics = monitor.getLastMetrics();
    res.json({
      hostname: os.hostname(),
      platform: os.platform(),
      arch: os.arch(),
      uptime: os.uptime(),
      device_id: process.env.STRATURA_DEVICE_ID || 'unknown',
      supervisor_version: process.env.npm_package_version || '1.0.0',
      metrics: metrics || {},
    });
  } catch (err) {
    next(err);
  }
});

router.get('/device/state', async (_req, res, next) => {
  try {
    const state = await stateManager.load();
    res.json(state);
  } catch (err) {
    next(err);
  }
});

router.post('/device/reboot', async (_req, res, next) => {
  try {
    logger.info('Reboot requested via API');
    res.json({ status: 'Reboot initiated' });
    setTimeout(() => {
      execFile('reboot', (err) => {
        if (err) { logger.error({ err: err.message }, 'Reboot failed'); }
      });
    }, 1000);
  } catch (err) {
    next(err);
  }
});

router.post('/device/shutdown', async (_req, res, next) => {
  try {
    logger.info('Shutdown requested via API');
    res.json({ status: 'Shutdown initiated' });
    setTimeout(() => {
      execFile('shutdown', ['-h', 'now'], (err) => {
        if (err) { logger.error({ err: err.message }, 'Shutdown failed'); }
      });
    }, 1000);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
