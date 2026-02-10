'use strict';

const { Router } = require('express');
const Joi = require('joi');
const containerManager = require('../services/container-manager');
const logger = require('../utils/logger');

const router = Router();

const logsQuerySchema = Joi.object({
  tail: Joi.number().integer().min(1).max(10000).default(100),
});

router.get('/containers', async (_req, res, next) => {
  try {
    const containers = await containerManager.listContainers();
    res.json(containers);
  } catch (err) {
    next(err);
  }
});

router.post('/containers/:id/start', async (req, res, next) => {
  try {
    await containerManager.startContainer(req.params.id);
    res.json({ status: 'started', id: req.params.id });
  } catch (err) {
    logger.error({ id: req.params.id, err: err.message }, 'Start failed');
    next(err);
  }
});

router.post('/containers/:id/stop', async (req, res, next) => {
  try {
    await containerManager.stopContainer(req.params.id);
    res.json({ status: 'stopped', id: req.params.id });
  } catch (err) {
    logger.error({ id: req.params.id, err: err.message }, 'Stop failed');
    next(err);
  }
});

router.post('/containers/:id/restart', async (req, res, next) => {
  try {
    await containerManager.restartContainer(req.params.id);
    res.json({ status: 'restarted', id: req.params.id });
  } catch (err) {
    logger.error({ id: req.params.id, err: err.message }, 'Restart failed');
    next(err);
  }
});

router.delete('/containers/:id', async (req, res, next) => {
  try {
    await containerManager.removeContainer(req.params.id, true);
    res.json({ status: 'removed', id: req.params.id });
  } catch (err) {
    logger.error({ id: req.params.id, err: err.message }, 'Remove failed');
    next(err);
  }
});

router.get('/containers/:id/logs', async (req, res, next) => {
  try {
    const { error, value } = logsQuerySchema.validate(req.query);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    const logs = await containerManager.getLogs(req.params.id, value.tail);
    res.type('text/plain').send(logs);
  } catch (err) {
    logger.error({ id: req.params.id, err: err.message }, 'Logs fetch failed');
    next(err);
  }
});

module.exports = router;
