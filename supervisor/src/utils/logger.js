'use strict';

const pino = require('pino');
const brand = require('./brand');

const level = process.env.LOG_LEVEL || 'info';

const logger = pino({
  level,
  name: `${brand.BRAND_PREFIX}-supervisor`,
  timestamp: pino.stdTimeFunctions.isoTime,
  formatters: {
    level(label) {
      return { level: label };
    },
  },
});

module.exports = logger;
