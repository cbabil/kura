'use strict';

// Mock all service dependencies before requiring the app

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

jest.mock('../src/config', () => ({
  loadConfig: jest.fn().mockReturnValue({
    api_endpoint: 'https://api.stratura.io',
    poll_interval: 60,
    applications: [],
    logging: { level: 'info', file: '/var/log/stratura/supervisor.log' },
    storage: { docker_root: '/var/lib/docker', data_root: '/var/lib/stratura' },
    network: { api_port: 48484, metrics_port: 9999 },
    security: { tls_enabled: false, api_key: 'test-api-key-12345' },
  }),
  loadSecurityConfig: jest.fn().mockReturnValue({
    container_security: {
      verify_signatures: true,
      allowed_registries: ['registry.stratura.io', 'docker.io'],
      seccomp_profile: 'default',
    },
    update_security: {
      verify_signatures: true,
      require_chain_of_trust: true,
      rollback_protection: true,
    },
  }),
}));

jest.mock('../src/services/container-manager', () => ({
  listContainers: jest.fn().mockResolvedValue([
    { id: 'abc123', name: 'myapp', image: 'myapp:1.0', state: 'running', status: 'Up', labels: {} },
  ]),
  startContainer: jest.fn().mockResolvedValue(),
  stopContainer: jest.fn().mockResolvedValue(),
  restartContainer: jest.fn().mockResolvedValue(),
  removeContainer: jest.fn().mockResolvedValue(),
  getLogs: jest.fn().mockResolvedValue('log line 1\nlog line 2'),
  inspectContainer: jest.fn().mockResolvedValue({
    State: { Status: 'running', Running: true, Health: { Status: 'healthy' } },
  }),
  healthCheck: jest.fn().mockResolvedValue([
    { name: 'myapp', status: 'running', health: 'healthy', running: true },
  ]),
  pullImage: jest.fn().mockResolvedValue(),
  createContainer: jest.fn().mockResolvedValue('new-id'),
}));

jest.mock('../src/services/state-manager', () => ({
  load: jest.fn().mockResolvedValue({
    version: '0.0.1',
    boot_count: 1,
    last_boot: '2025-01-01T00:00:00.000Z',
    update_status: { last_update: null, current_version: '0.0.1', update_state: 'idle' },
    network_status: { connected: false, interface: null, ip_address: null },
    containers: {},
    provisioning: { completed: true, timestamp: '2025-01-01T00:00:00.000Z' },
  }),
  save: jest.fn().mockResolvedValue(),
  getDefaultState: jest.fn().mockReturnValue({ version: '0.0.1', boot_count: 0 }),
  updateBootCount: jest.fn().mockResolvedValue({ boot_count: 1 }),
  updateNetworkStatus: jest.fn().mockResolvedValue(),
  updateContainerStatus: jest.fn().mockResolvedValue(),
  setProvisioningComplete: jest.fn().mockResolvedValue(),
}));

jest.mock('../src/services/update-manager', () => ({
  getUpdateStatus: jest.fn().mockReturnValue({ state: 'idle', error: null, progress: null }),
  triggerUpdate: jest.fn().mockResolvedValue(),
  acquireLock: jest.fn().mockResolvedValue(jest.fn()),
  releaseLock: jest.fn().mockResolvedValue(),
  resetState: jest.fn(),
  checkForUpdates: jest.fn().mockResolvedValue({ available: false }),
}));

jest.mock('../src/services/monitor', () => ({
  collectMetrics: jest.fn().mockResolvedValue({ cpu: { usage: 45 } }),
  checkThresholds: jest.fn().mockReturnValue([]),
  getPrometheusMetrics: jest.fn().mockResolvedValue(
    '# HELP system_cpu_usage CPU usage %\nsystem_cpu_usage 42\n',
  ),
  getLastMetrics: jest.fn().mockReturnValue({ cpu: { usage: 45 }, memory: { usedPercent: 50 } }),
  setContainerMetric: jest.fn(),
}));

jest.mock('../src/services/provisioning-manager', () => ({
  isProvisioned: jest.fn().mockResolvedValue(true),
  provision: jest.fn().mockResolvedValue(true),
}));

jest.mock('node-cron', () => ({
  schedule: jest.fn().mockReturnValue({ stop: jest.fn() }),
}));

jest.mock('child_process', () => ({
  execFile: jest.fn(),
}));

const supertest = require('supertest');
const { app } = require('../src/index');
const containerManager = require('../src/services/container-manager');
const updateManager = require('../src/services/update-manager');

const API_KEY = 'test-api-key-12345';

function request() {
  return supertest(app);
}

describe('API endpoints', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Restore default mock returns after clearAllMocks
    containerManager.listContainers.mockResolvedValue([
      { id: 'abc123', name: 'myapp', image: 'myapp:1.0', state: 'running', status: 'Up', labels: {} },
    ]);
    containerManager.startContainer.mockResolvedValue();
    containerManager.stopContainer.mockResolvedValue();
    containerManager.restartContainer.mockResolvedValue();
    containerManager.removeContainer.mockResolvedValue();
    containerManager.getLogs.mockResolvedValue('log line 1\nlog line 2');
    containerManager.healthCheck.mockResolvedValue([
      { name: 'myapp', status: 'running', health: 'healthy', running: true },
    ]);

    updateManager.getUpdateStatus.mockReturnValue({ state: 'idle', error: null, progress: null });
    updateManager.triggerUpdate.mockResolvedValue();
    updateManager.acquireLock.mockResolvedValue(jest.fn());
    updateManager.resetState.mockImplementation(() => {});
  });

  describe('GET /v1/health', () => {
    it('returns 200 with status', async () => {
      const res = await request().get('/v1/health');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status');
      expect(res.body).toHaveProperty('uptime');
      expect(res.body).toHaveProperty('timestamp');
    });

    it('skips authentication', async () => {
      const res = await request().get('/v1/health');
      expect(res.status).toBe(200);
    });

    it('returns containers array', async () => {
      const res = await request().get('/v1/health');
      expect(res.body).toHaveProperty('containers');
      expect(Array.isArray(res.body.containers)).toBe(true);
    });

    it('returns healthy when all containers are running', async () => {
      const res = await request().get('/v1/health');
      expect(res.body.status).toBe('healthy');
    });

    it('returns degraded when a container is not running', async () => {
      containerManager.healthCheck.mockResolvedValueOnce([
        { name: 'app1', status: 'running', health: 'healthy', running: true },
        { name: 'app2', status: 'exited', health: 'unknown', running: false },
      ]);

      const res = await request().get('/v1/health');
      expect(res.status).toBe(503);
      expect(res.body.status).toBe('degraded');
    });

    it('returns healthy when healthCheck throws', async () => {
      containerManager.healthCheck.mockRejectedValueOnce(new Error('Docker unavailable'));

      const res = await request().get('/v1/health');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('healthy');
      expect(res.body.containers).toEqual([]);
    });
  });

  describe('GET /v1/device', () => {
    it('returns device info with valid API key', async () => {
      const res = await request()
        .get('/v1/device')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('hostname');
      expect(res.body).toHaveProperty('platform');
      expect(res.body).toHaveProperty('arch');
      expect(res.body).toHaveProperty('uptime');
      expect(res.body).toHaveProperty('device_id');
      expect(res.body).toHaveProperty('supervisor_version');
    });

    it('returns 401 without API key', async () => {
      const res = await request().get('/v1/device');
      expect(res.status).toBe(401);
      expect(res.body).toHaveProperty('error', 'API key required');
    });

    it('returns 403 with invalid API key', async () => {
      const res = await request()
        .get('/v1/device')
        .set('x-api-key', 'wrong-key');

      expect(res.status).toBe(403);
      expect(res.body).toHaveProperty('error', 'Invalid API key');
    });

    it('includes metrics object in response', async () => {
      const res = await request()
        .get('/v1/device')
        .set('x-api-key', API_KEY);

      expect(res.body).toHaveProperty('metrics');
    });
  });

  describe('GET /v1/device/state', () => {
    it('returns device state', async () => {
      const res = await request()
        .get('/v1/device/state')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('version');
      expect(res.body).toHaveProperty('boot_count');
      expect(res.body).toHaveProperty('containers');
    });

    it('requires authentication', async () => {
      const res = await request().get('/v1/device/state');
      expect(res.status).toBe(401);
    });
  });

  describe('POST /v1/device/reboot', () => {
    it('returns 200 with reboot status', async () => {
      const res = await request()
        .post('/v1/device/reboot')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'Reboot initiated');
    });

    it('requires authentication', async () => {
      const res = await request().post('/v1/device/reboot');
      expect(res.status).toBe(401);
    });
  });

  describe('POST /v1/device/shutdown', () => {
    it('returns 200 with shutdown status', async () => {
      const res = await request()
        .post('/v1/device/shutdown')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'Shutdown initiated');
    });

    it('requires authentication', async () => {
      const res = await request().post('/v1/device/shutdown');
      expect(res.status).toBe(401);
    });
  });

  describe('GET /v1/containers', () => {
    it('returns container list', async () => {
      const res = await request()
        .get('/v1/containers')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
      expect(res.body[0]).toHaveProperty('id', 'abc123');
    });

    it('requires authentication', async () => {
      const res = await request().get('/v1/containers');
      expect(res.status).toBe(401);
    });
  });

  describe('POST /v1/containers/:id/start', () => {
    it('returns 200 with started status', async () => {
      const res = await request()
        .post('/v1/containers/abc123/start')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'started');
      expect(res.body).toHaveProperty('id', 'abc123');
    });

    it('returns 500 when container start fails', async () => {
      containerManager.startContainer.mockRejectedValueOnce(new Error('container not found'));

      const res = await request()
        .post('/v1/containers/nonexistent/start')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(500);
      expect(res.body).toHaveProperty('error');
    });
  });

  describe('POST /v1/containers/:id/stop', () => {
    it('returns 200 with stopped status', async () => {
      const res = await request()
        .post('/v1/containers/abc123/stop')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'stopped');
    });

    it('returns error when stop fails with statusCode', async () => {
      const err = new Error('Not found');
      err.statusCode = 404;
      containerManager.stopContainer.mockRejectedValueOnce(err);

      const res = await request()
        .post('/v1/containers/missing/stop')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(404);
      expect(res.body.error).toBe('Not found');
    });
  });

  describe('POST /v1/containers/:id/restart', () => {
    it('returns 200 with restarted status', async () => {
      const res = await request()
        .post('/v1/containers/abc123/restart')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'restarted');
    });
  });

  describe('DELETE /v1/containers/:id', () => {
    it('returns 200 with removed status', async () => {
      const res = await request()
        .delete('/v1/containers/abc123')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'removed');
    });

    it('calls removeContainer with force=true', async () => {
      await request()
        .delete('/v1/containers/abc123')
        .set('x-api-key', API_KEY);

      expect(containerManager.removeContainer).toHaveBeenCalledWith('abc123', true);
    });
  });

  describe('GET /v1/containers/:id/logs', () => {
    it('returns log text', async () => {
      const res = await request()
        .get('/v1/containers/abc123/logs')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.type).toMatch(/text\/plain/);
      expect(res.text).toContain('log line 1');
    });

    it('accepts custom tail parameter', async () => {
      await request()
        .get('/v1/containers/abc123/logs?tail=50')
        .set('x-api-key', API_KEY);

      expect(containerManager.getLogs).toHaveBeenCalledWith('abc123', 50);
    });

    it('rejects invalid tail parameter', async () => {
      const res = await request()
        .get('/v1/containers/abc123/logs?tail=-1')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(400);
      expect(res.body).toHaveProperty('error');
    });

    it('rejects tail parameter above 10000', async () => {
      const res = await request()
        .get('/v1/containers/abc123/logs?tail=20000')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(400);
    });
  });

  describe('POST /v1/update', () => {
    it('triggers update with valid body', async () => {
      const res = await request()
        .post('/v1/update')
        .set('x-api-key', API_KEY)
        .send({ containerId: 'abc123', image: 'myapp:2.0' });

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'Update triggered');
      expect(res.body).toHaveProperty('containerId', 'abc123');
      expect(res.body).toHaveProperty('image', 'myapp:2.0');
    });

    it('returns 400 for missing containerId', async () => {
      const res = await request()
        .post('/v1/update')
        .set('x-api-key', API_KEY)
        .send({ image: 'myapp:2.0' });

      expect(res.status).toBe(400);
      expect(res.body).toHaveProperty('error');
    });

    it('returns 400 for missing image', async () => {
      const res = await request()
        .post('/v1/update')
        .set('x-api-key', API_KEY)
        .send({ containerId: 'abc123' });

      expect(res.status).toBe(400);
      expect(res.body).toHaveProperty('error');
    });

    it('returns 400 for empty body', async () => {
      const res = await request()
        .post('/v1/update')
        .set('x-api-key', API_KEY)
        .send({});

      expect(res.status).toBe(400);
    });

    it('requires authentication', async () => {
      const res = await request()
        .post('/v1/update')
        .send({ containerId: 'abc123', image: 'myapp:2.0' });

      expect(res.status).toBe(401);
    });

    it('passes error to handler when triggerUpdate fails', async () => {
      updateManager.triggerUpdate.mockRejectedValueOnce(new Error('Update in progress'));

      const res = await request()
        .post('/v1/update')
        .set('x-api-key', API_KEY)
        .send({ containerId: 'abc123', image: 'myapp:2.0' });

      expect(res.status).toBe(500);
      expect(res.body).toHaveProperty('error');
    });
  });

  describe('GET /v1/update/status', () => {
    it('returns update state', async () => {
      const res = await request()
        .get('/v1/update/status')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('state', 'idle');
      expect(res.body).toHaveProperty('error', null);
      expect(res.body).toHaveProperty('progress', null);
    });

    it('requires authentication', async () => {
      const res = await request().get('/v1/update/status');
      expect(res.status).toBe(401);
    });
  });

  describe('POST /v1/update/lock', () => {
    it('acquires lock and returns 200', async () => {
      const res = await request()
        .post('/v1/update/lock')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'Lock acquired');
    });

    it('returns error when lock fails', async () => {
      updateManager.acquireLock.mockRejectedValueOnce(new Error('lock busy'));

      const res = await request()
        .post('/v1/update/lock')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(500);
    });
  });

  describe('DELETE /v1/update/lock', () => {
    it('releases lock and resets state', async () => {
      const res = await request()
        .delete('/v1/update/lock')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'Lock released and state reset');
      expect(updateManager.resetState).toHaveBeenCalled();
    });
  });

  describe('GET /v1/metrics', () => {
    it('returns Prometheus text format', async () => {
      const monitor = require('../src/services/monitor');
      const res = await request()
        .get('/v1/metrics')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(200);
      expect(res.type).toMatch(/text\/plain/);
      expect(res.text).toContain('system_cpu_usage');
    });

    it('requires authentication', async () => {
      const res = await request().get('/v1/metrics');
      expect(res.status).toBe(401);
    });
  });

  describe('Error handler', () => {
    it('returns JSON error response for 500 errors', async () => {
      containerManager.restartContainer.mockRejectedValueOnce(new Error('Docker error'));

      const res = await request()
        .post('/v1/containers/bad/restart')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(500);
      expect(res.body).toHaveProperty('error', 'Internal server error');
      expect(res.headers['content-type']).toMatch(/json/);
    });

    it('uses error statusCode if provided', async () => {
      const err = new Error('Not found');
      err.statusCode = 404;
      containerManager.startContainer.mockRejectedValueOnce(err);

      const res = await request()
        .post('/v1/containers/missing/start')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(404);
      expect(res.body.error).toBe('Not found');
    });

    it('hides error message for 500 status', async () => {
      containerManager.listContainers.mockRejectedValueOnce(new Error('sensitive db info'));

      const res = await request()
        .get('/v1/containers')
        .set('x-api-key', API_KEY);

      expect(res.status).toBe(500);
      expect(res.body.error).toBe('Internal server error');
      expect(res.body.error).not.toContain('sensitive');
    });
  });
});
