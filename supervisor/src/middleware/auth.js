'use strict';

const logger = require('../utils/logger');

const SKIP_AUTH_PATHS = ['/v1/health'];

function createAuthMiddleware(config) {
  const apiKey = config.security?.api_key || process.env.STRATURA_API_KEY || '';

  return (req, res, next) => {
    if (SKIP_AUTH_PATHS.includes(req.path)) {
      return next();
    }

    if (!apiKey) {
      logger.warn('No API key configured, authentication disabled');
      return next();
    }

    const provided = req.headers['x-api-key'];

    if (!provided) {
      logger.warn({ path: req.path, ip: req.ip }, 'Missing API key');
      return res.status(401).json({ error: 'API key required' });
    }

    if (provided !== apiKey) {
      logger.warn({ path: req.path, ip: req.ip }, 'Invalid API key');
      return res.status(403).json({ error: 'Invalid API key' });
    }

    return next();
  };
}

module.exports = { createAuthMiddleware };
