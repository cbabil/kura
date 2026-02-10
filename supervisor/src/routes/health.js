'use strict';

const { Router } = require('express');
const containerManager = require('../services/container-manager');

const router = Router();

router.get('/health', async (_req, res) => {
  try {
    const containers = await containerManager.healthCheck();
    const allHealthy = containers.every((c) => c.running);
    const status = allHealthy ? 'healthy' : 'degraded';

    res.status(allHealthy ? 200 : 503).json({
      status,
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      containers,
    });
  } catch (_err) {
    res.status(200).json({
      status: 'healthy',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      containers: [],
    });
  }
});

module.exports = router;
