'use strict';

const { Router } = require('express');
const Joi = require('joi');
const updateManager = require('../services/update-manager');
const logger = require('../utils/logger');

const router = Router();

const updateSchema = Joi.object({
  containerId: Joi.string().required(),
  image: Joi.string().required(),
});

router.post('/update', async (req, res, next) => {
  try {
    const { error, value } = updateSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    await updateManager.triggerUpdate(value.containerId, value.image);
    res.json({ status: 'Update triggered', containerId: value.containerId, image: value.image });
  } catch (err) {
    logger.error({ err: err.message }, 'Update trigger failed');
    next(err);
  }
});

router.get('/update/status', async (_req, res, next) => {
  try {
    const status = updateManager.getUpdateStatus();
    res.json(status);
  } catch (err) {
    next(err);
  }
});

router.post('/update/lock', async (_req, res, next) => {
  try {
    const release = await updateManager.acquireLock();
    res.json({ status: 'Lock acquired' });
    setTimeout(() => {
      updateManager.releaseLock(release).catch((err) => {
        logger.error({ err: err.message }, 'Auto-release lock failed');
      });
    }, 300000);
  } catch (err) {
    logger.error({ err: err.message }, 'Lock acquire failed');
    next(err);
  }
});

router.delete('/update/lock', async (_req, res, next) => {
  try {
    updateManager.resetState();
    res.json({ status: 'Lock released and state reset' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
