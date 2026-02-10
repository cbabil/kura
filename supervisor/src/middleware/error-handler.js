'use strict';

const logger = require('../utils/logger');

function errorHandler(err, _req, res, _next) {
  const status = err.statusCode || err.status || 500;
  const message = status === 500 ? 'Internal server error' : err.message;

  logger.error({
    err: err.message,
    stack: err.stack,
    status,
  }, 'Request error');

  res.status(status).json({ error: message });
}

module.exports = { errorHandler };
