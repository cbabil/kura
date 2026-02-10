'use strict';

const { Router } = require('express');
const monitor = require('../services/monitor');

const router = Router();

router.get('/metrics', async (_req, res, next) => {
  try {
    const metrics = await monitor.getPrometheusMetrics();
    res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    res.send(metrics);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
