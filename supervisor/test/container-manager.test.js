'use strict';

const {
  mockStart, mockStop, mockRestart, mockRemove, mockLogs, mockInspect,
  mockCreateContainer, mockListContainers, mockGetContainer,
  mockPull, mockFollowProgress,
} = require('./helpers/dockerode-mock');

jest.mock('dockerode', () => require('./helpers/dockerode-mock').dockerodeMockFactory());

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const containerManager = require('../src/services/container-manager');
const { ENV_PREFIX, LABELS } = require('../src/utils/constants');

describe('container-manager', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('listContainers', () => {
    it('returns formatted containers filtered by managed label', async () => {
      mockListContainers.mockResolvedValueOnce([
        {
          Id: 'abc123',
          Names: ['/myapp'],
          Image: 'myapp:latest',
          State: 'running',
          Status: 'Up 2 hours',
          Labels: { [LABELS.MANAGED]: 'true' },
        },
      ]);

      const result = await containerManager.listContainers();

      expect(mockListContainers).toHaveBeenCalledWith({
        all: true,
        filters: { label: [`${LABELS.MANAGED}=true`] },
      });
      expect(result).toEqual([
        {
          id: 'abc123',
          name: 'myapp',
          image: 'myapp:latest',
          state: 'running',
          status: 'Up 2 hours',
          labels: { [LABELS.MANAGED]: 'true' },
        },
      ]);
    });

    it('returns empty array when no managed containers exist', async () => {
      mockListContainers.mockResolvedValueOnce([]);
      const result = await containerManager.listContainers();
      expect(result).toEqual([]);
    });

    it('strips leading slash from container names', async () => {
      mockListContainers.mockResolvedValueOnce([
        {
          Id: 'x1',
          Names: ['/my-service'],
          Image: 'img:1',
          State: 'running',
          Status: 'Up',
          Labels: {},
        },
      ]);
      const result = await containerManager.listContainers();
      expect(result[0].name).toBe('my-service');
    });

    it('passes all=false when requested', async () => {
      mockListContainers.mockResolvedValueOnce([]);
      await containerManager.listContainers(false);
      expect(mockListContainers).toHaveBeenCalledWith(
        expect.objectContaining({ all: false }),
      );
    });

    it('propagates Docker errors', async () => {
      mockListContainers.mockRejectedValueOnce(new Error('Docker socket not available'));
      await expect(containerManager.listContainers()).rejects.toThrow('Docker socket not available');
    });
  });

  describe('createContainer', () => {
    it('creates container with minimal config (name + image)', async () => {
      const config = { name: 'myapp', image: 'myapp:latest' };
      const id = await containerManager.createContainer(config);

      expect(mockCreateContainer).toHaveBeenCalledTimes(1);
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.Image).toBe('myapp:latest');
      expect(opts.name).toBe('myapp');
      expect(id).toBe('new-container-id');
    });

    it('starts the container after creation', async () => {
      await containerManager.createContainer({ name: 'a', image: 'b' });
      expect(mockStart).toHaveBeenCalledTimes(1);
    });

    it('builds security options with cap_drop ALL by default', async () => {
      await containerManager.createContainer({ name: 'a', image: 'b' });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.CapDrop).toEqual(['ALL']);
    });

    it('sets no-new-privileges and default seccomp profile', async () => {
      await containerManager.createContainer({ name: 'a', image: 'b' });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.SecurityOpt).toContain('no-new-privileges');
      expect(opts.HostConfig.SecurityOpt).toContain('seccomp=default');
    });

    it('uses seccomp=unconfined when privileged', async () => {
      await containerManager.createContainer({ name: 'a', image: 'b', privileged: true });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.SecurityOpt).toContain('seccomp=unconfined');
    });

    it('adds specified capabilities', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        capabilities: ['NET_BIND_SERVICE'],
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.CapAdd).toEqual(['NET_BIND_SERVICE']);
    });

    it('sets read-only root filesystem', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        read_only: true,
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.ReadonlyRootfs).toBe(true);
    });

    it('sets resource limits (memory and cpu_shares)', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        resources: { memory: '512m', cpu_shares: 512 },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.Memory).toBe(512 * 1024 * 1024);
      expect(opts.HostConfig.CpuShares).toBe(512);
    });

    it('defaults memory to 256m and cpu_shares to 1024', async () => {
      await containerManager.createContainer({ name: 'a', image: 'b' });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.Memory).toBe(256 * 1024 * 1024);
      expect(opts.HostConfig.CpuShares).toBe(1024);
    });

    it('parses memory in gigabytes', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        resources: { memory: '1g' },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.Memory).toBe(1024 * 1024 * 1024);
    });

    it('parses memory in kilobytes (clamped to 4MB minimum)', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        resources: { memory: '1024k' },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.Memory).toBe(4 * 1024 * 1024);
    });

    it('sets host network mode', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        network: { type: 'host' },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.NetworkMode).toBe('host');
      expect(opts.HostConfig.PortBindings).toEqual({});
    });

    it('sets bridge network mode with string port mappings', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        network: { ports: ['8080:80'] },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.NetworkMode).toBe('bridge');
      expect(opts.HostConfig.PortBindings).toEqual({
        '80/tcp': [{ HostPort: '8080' }],
      });
    });

    it('sets port bindings from object config', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        network: {
          ports: [{ host: 9090, container: 80, protocol: 'udp' }],
        },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.PortBindings).toEqual({
        '80/udp': [{ HostPort: '9090' }],
      });
    });

    it('builds volume binds from string config', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        volumes: ['/var/lib/myapp:/container/path:ro'],
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.Binds).toEqual(['/var/lib/myapp:/container/path:ro']);
    });

    it('builds volume binds from object config', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        volumes: [{ host_path: '/var/lib/data', container_path: '/app/data', mode: 'rw' }],
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.Binds).toEqual(['/var/lib/data:/app/data:rw']);
    });

    it('sets managed labels', async () => {
      await containerManager.createContainer({
        name: 'myapp',
        image: 'img:1',
        version: '2.0',
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.Labels[LABELS.MANAGED]).toBe('true');
      expect(opts.Labels[LABELS.APP_NAME]).toBe('myapp');
      expect(opts.Labels[LABELS.APP_VERSION]).toBe('2.0');
    });

    it('sets healthcheck when provided', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        healthcheck: { cmd: 'curl http://localhost', interval: '10s', timeout: '3s', retries: 5 },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.Healthcheck).toEqual({
        Test: ['CMD-SHELL', 'curl http://localhost'],
        Interval: 10 * 1e9,
        Timeout: 3 * 1e9,
        Retries: 5,
      });
    });

    it('does not set Healthcheck when not provided', async () => {
      await containerManager.createContainer({ name: 'a', image: 'b' });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.Healthcheck).toBeUndefined();
    });

    it('builds environment variables with branded prefix', async () => {
      await containerManager.createContainer({
        name: 'myapp',
        image: 'b',
        version: '1.0',
        environment: { MY_VAR: 'hello' },
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.Env).toContain(`${ENV_PREFIX}_APP_NAME=myapp`);
      expect(opts.Env).toContain('MY_VAR=hello');
    });

    it('sets restart policy from config', async () => {
      await containerManager.createContainer({
        name: 'a',
        image: 'b',
        restart_policy: 'on-failure',
      });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.RestartPolicy).toEqual({ Name: 'on-failure' });
    });

    it('defaults restart policy to always', async () => {
      await containerManager.createContainer({ name: 'a', image: 'b' });
      const opts = mockCreateContainer.mock.calls[0][0];
      expect(opts.HostConfig.RestartPolicy).toEqual({ Name: 'always' });
    });
  });

  describe('only acts on containers the supervisor manages', () => {
    // Tomo's containers (tomo-proxy, apps) share the Docker daemon and must be
    // out of reach of cloud commands.
    const unmanaged = {
      State: { Status: 'running', Running: true },
      Config: { Image: 'traefik:v3.3', Labels: { 'tomo.managed': 'true' } },
      Name: '/tomo-proxy',
    };

    it.each([
      ['startContainer', () => containerManager.startContainer('tomo-proxy'), mockStart],
      ['stopContainer', () => containerManager.stopContainer('tomo-proxy'), mockStop],
      ['restartContainer', () => containerManager.restartContainer('tomo-proxy'), mockRestart],
      ['removeContainer', () => containerManager.removeContainer('tomo-proxy', true), mockRemove],
      ['getLogs', () => containerManager.getLogs('tomo-proxy'), mockLogs],
      ['inspectContainer', () => containerManager.inspectContainer('tomo-proxy'), jest.fn()],
    ])('%s refuses an unmanaged container', async (_name, call, action) => {
      mockInspect.mockResolvedValueOnce(unmanaged);
      await expect(call()).rejects.toThrow('not managed');
      expect(action).not.toHaveBeenCalled();
    });

    it('refuses a container with no labels at all', async () => {
      mockInspect.mockResolvedValueOnce({ Config: {}, Name: '/bare' });
      await expect(containerManager.stopContainer('bare')).rejects.toThrow('not managed');
      expect(mockStop).not.toHaveBeenCalled();
    });

    it('acts on a managed container', async () => {
      await containerManager.stopContainer('myapp');
      expect(mockStop).toHaveBeenCalled();
    });
  });

  describe('startContainer', () => {
    it('calls start on the correct container', async () => {
      await containerManager.startContainer('abc123');
      expect(mockGetContainer).toHaveBeenCalledWith('abc123');
      expect(mockStart).toHaveBeenCalledTimes(1);
    });
  });

  describe('stopContainer', () => {
    it('calls stop on the correct container', async () => {
      await containerManager.stopContainer('abc123');
      expect(mockGetContainer).toHaveBeenCalledWith('abc123');
      expect(mockStop).toHaveBeenCalledTimes(1);
    });
  });

  describe('restartContainer', () => {
    it('calls restart on the correct container', async () => {
      await containerManager.restartContainer('abc123');
      expect(mockGetContainer).toHaveBeenCalledWith('abc123');
      expect(mockRestart).toHaveBeenCalledTimes(1);
    });
  });

  describe('removeContainer', () => {
    it('removes container without force by default', async () => {
      await containerManager.removeContainer('abc123');
      expect(mockRemove).toHaveBeenCalledWith({ force: false });
    });

    it('removes container with force when specified', async () => {
      await containerManager.removeContainer('abc123', true);
      expect(mockRemove).toHaveBeenCalledWith({ force: true });
    });
  });

  describe('getLogs', () => {
    it('returns combined stdout/stderr output', async () => {
      const logs = await containerManager.getLogs('abc123');
      expect(mockLogs).toHaveBeenCalledWith({ stdout: true, stderr: true, tail: 100 });
      expect(logs).toContain('log line 1');
    });

    it('respects custom tail parameter', async () => {
      await containerManager.getLogs('abc123', 50);
      expect(mockLogs).toHaveBeenCalledWith({ stdout: true, stderr: true, tail: 50 });
    });
  });

  describe('inspectContainer', () => {
    it('returns container inspection details', async () => {
      const result = await containerManager.inspectContainer('abc123');
      expect(mockGetContainer).toHaveBeenCalledWith('abc123');
      expect(result.State.Status).toBe('running');
    });
  });

  describe('healthCheck', () => {
    it('returns status array for all managed containers', async () => {
      mockListContainers.mockResolvedValueOnce([
        { Id: 'c1', Names: ['/app1'] },
        { Id: 'c2', Names: ['/app2'] },
      ]);

      const result = await containerManager.healthCheck();

      expect(result).toHaveLength(2);
      expect(result[0]).toEqual({
        name: 'app1',
        status: 'running',
        health: 'healthy',
        running: true,
      });
    });

    it('handles missing health status', async () => {
      mockListContainers.mockResolvedValueOnce([
        { Id: 'c1', Names: ['/app1'] },
      ]);
      mockGetContainer.mockReturnValueOnce({
        inspect: jest.fn().mockResolvedValue({
          State: { Status: 'running', Running: true },
        }),
      });

      const result = await containerManager.healthCheck();
      expect(result[0].health).toBe('unknown');
    });

    it('returns empty array when no containers exist', async () => {
      mockListContainers.mockResolvedValueOnce([]);
      const result = await containerManager.healthCheck();
      expect(result).toEqual([]);
    });
  });

  describe('pullImage', () => {
    it('pulls image and follows progress', async () => {
      const result = await containerManager.pullImage('myapp:2.0');
      expect(mockPull).toHaveBeenCalledWith('myapp:2.0');
      expect(result).toEqual([{ status: 'done' }]);
    });

    it('rejects when pull progress fails', async () => {
      mockFollowProgress.mockImplementationOnce((_stream, cb) => {
        cb(new Error('pull failed'), null);
      });
      await expect(containerManager.pullImage('bad:img')).rejects.toThrow('pull failed');
    });
  });
});
