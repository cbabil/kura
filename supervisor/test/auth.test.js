'use strict';

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const { createAuthMiddleware } = require('../src/middleware/auth');

function mockReqRes(path, headers = {}) {
  const req = { path, headers, ip: '127.0.0.1' };
  const res = {
    status: jest.fn().mockReturnThis(),
    json: jest.fn().mockReturnThis(),
  };
  const next = jest.fn();
  return { req, res, next };
}

describe('auth middleware', () => {
  it('skips auth for /v1/health', () => {
    const middleware = createAuthMiddleware({ security: { api_key: 'secret' } });
    const { req, res, next } = mockReqRes('/v1/health');

    middleware(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });

  it('allows request when no API key configured', () => {
    const middleware = createAuthMiddleware({ security: {} });
    const { req, res, next } = mockReqRes('/v1/device');

    middleware(req, res, next);
    expect(next).toHaveBeenCalled();
  });

  it('allows request when security section is missing', () => {
    const middleware = createAuthMiddleware({});
    const { req, res, next } = mockReqRes('/v1/device');

    middleware(req, res, next);
    expect(next).toHaveBeenCalled();
  });

  it('returns 401 when API key required but not provided', () => {
    const middleware = createAuthMiddleware({ security: { api_key: 'secret' } });
    const { req, res, next } = mockReqRes('/v1/device');

    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.json).toHaveBeenCalledWith({ error: 'API key required' });
    expect(next).not.toHaveBeenCalled();
  });

  it('returns 403 when API key is wrong', () => {
    const middleware = createAuthMiddleware({ security: { api_key: 'secret' } });
    const { req, res, next } = mockReqRes('/v1/device', { 'x-api-key': 'wrong' });

    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(403);
    expect(res.json).toHaveBeenCalledWith({ error: 'Invalid API key' });
  });

  it('allows request with correct API key', () => {
    const middleware = createAuthMiddleware({ security: { api_key: 'secret' } });
    const { req, res, next } = mockReqRes('/v1/device', { 'x-api-key': 'secret' });

    middleware(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });

  it('uses STRATURA_API_KEY env var as fallback', () => {
    const original = process.env.STRATURA_API_KEY;
    process.env.STRATURA_API_KEY = 'env-key';

    const middleware = createAuthMiddleware({ security: {} });
    const { req, res, next } = mockReqRes('/v1/device', { 'x-api-key': 'env-key' });

    middleware(req, res, next);
    expect(next).toHaveBeenCalled();

    process.env.STRATURA_API_KEY = original || '';
  });
});
