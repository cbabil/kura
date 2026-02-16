'use strict';

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const containerOpts = require('../src/services/container-opts');
const { ENV_PREFIX, LABELS } = require('../src/utils/constants');

describe('container-opts', () => {
  describe('buildSecurityOpts', () => {
    it('defaults to non-privileged, read-write, no extra capabilities', () => {
      const opts = containerOpts.buildSecurityOpts({});
      expect(opts.capDrop).toEqual(['ALL']);
      expect(opts.capAdd).toEqual([]);
      expect(opts.readOnly).toBe(false);
      expect(opts.securityOpt).toContain('seccomp=default');
    });
  });

  describe('buildResourceOpts', () => {
    it('defaults to 256m memory and 1024 cpu_shares', () => {
      const opts = containerOpts.buildResourceOpts({});
      expect(opts.memory).toBe(256 * 1024 * 1024);
      expect(opts.cpuShares).toBe(1024);
    });

    it('parses memory with no unit suffix as megabytes', () => {
      const opts = containerOpts.buildResourceOpts({ resources: { memory: '512' } });
      expect(opts.memory).toBe(512 * 1024 * 1024);
    });

    it('returns default 256m for invalid memory string', () => {
      const opts = containerOpts.buildResourceOpts({ resources: { memory: 'invalid' } });
      expect(opts.memory).toBe(256 * 1024 * 1024);
    });
  });

  describe('buildNetworkOpts', () => {
    it('defaults to bridge mode with no ports', () => {
      const opts = containerOpts.buildNetworkOpts({});
      expect(opts.networkMode).toBe('bridge');
      expect(opts.portBindings).toEqual({});
    });

    it('handles port object without protocol (defaults to tcp)', () => {
      const opts = containerOpts.buildNetworkOpts({
        network: { ports: [{ host: 8080, container: 80 }] },
      });
      expect(opts.portBindings['80/tcp']).toEqual([{ HostPort: '8080' }]);
    });

    it('uses custom network mode', () => {
      const opts = containerOpts.buildNetworkOpts({ network: { mode: 'none' } });
      expect(opts.networkMode).toBe('none');
    });

    it('rejects invalid port string format (no colon)', () => {
      expect(() => containerOpts.buildNetworkOpts({
        network: { ports: ['8080'] },
      })).toThrow('Invalid port mapping format');
    });

    it('parses valid port string', () => {
      const opts = containerOpts.buildNetworkOpts({
        network: { ports: ['8080:80'] },
      });
      expect(opts.portBindings['80/tcp']).toEqual([{ HostPort: '8080' }]);
    });
  });

  describe('buildEnv', () => {
    it('includes branded base env vars', () => {
      const env = containerOpts.buildEnv({ name: 'app1' });
      expect(env).toContain(`${ENV_PREFIX}_APP_NAME=app1`);
      expect(env).toContain(`${ENV_PREFIX}_APP_VERSION=latest`);
    });
  });

  describe('buildBinds', () => {
    it('returns empty array with no volumes', () => {
      const binds = containerOpts.buildBinds({});
      expect(binds).toEqual([]);
    });

    it('handles volume object with default mode', () => {
      const binds = containerOpts.buildBinds({
        volumes: [{ host_path: '/var/lib/app', container_path: '/b' }],
      });
      expect(binds).toEqual(['/var/lib/app:/b:rw']);
    });

    it('validates string volumes against allowed roots', () => {
      expect(() => containerOpts.buildBinds({
        volumes: ['/etc/shadow:/data:ro'],
      })).toThrow('not under allowed roots');
    });

    it('allows string volumes under allowed roots', () => {
      const binds = containerOpts.buildBinds({
        volumes: ['/var/lib/app:/data:ro'],
      });
      expect(binds).toEqual(['/var/lib/app:/data:ro']);
    });

    it('rejects object volumes outside allowed roots', () => {
      expect(() => containerOpts.buildBinds({
        volumes: [{ host_path: '/etc/passwd', container_path: '/data' }],
      })).toThrow('not under allowed roots');
    });

    it('rejects traversal via parent directory', () => {
      expect(() => containerOpts.buildBinds({
        volumes: [{ host_path: '/var/lib/../../etc/shadow', container_path: '/data' }],
      })).toThrow('not under allowed roots');
    });

    it('rejects empty host_path', () => {
      expect(() => containerOpts.buildBinds({
        volumes: [{ host_path: '', container_path: '/data' }],
      })).toThrow('host_path is required');
    });

    it('rejects non-string host_path', () => {
      expect(() => containerOpts.buildBinds({
        volumes: [{ host_path: 123, container_path: '/data' }],
      })).toThrow('host_path is required');
    });

    it('rejects relative host_path', () => {
      expect(() => containerOpts.buildBinds({
        volumes: [{ host_path: 'relative/path', container_path: '/data' }],
      })).toThrow('must be absolute');
    });

    it('rejects host_path with null bytes', () => {
      expect(() => containerOpts.buildBinds({
        volumes: [{ host_path: '/var/lib/app\x00evil', container_path: '/data' }],
      })).toThrow('null bytes');
    });
  });

  describe('buildLabels', () => {
    it('defaults version to latest', () => {
      const labels = containerOpts.buildLabels({ name: 'app' });
      expect(labels[LABELS.APP_VERSION]).toBe('latest');
    });
  });

  describe('buildHealthcheck', () => {
    it('returns null when no healthcheck provided', () => {
      expect(containerOpts.buildHealthcheck({})).toBeNull();
    });

    it('returns null when healthcheck has no cmd', () => {
      expect(containerOpts.buildHealthcheck({ healthcheck: {} })).toBeNull();
    });

    it('uses default interval/timeout/retries', () => {
      const hc = containerOpts.buildHealthcheck({
        healthcheck: { cmd: 'test' },
      });
      expect(hc.Interval).toBe(30 * 1e9);
      expect(hc.Timeout).toBe(5 * 1e9);
      expect(hc.Retries).toBe(3);
    });

    it('parses millisecond duration', () => {
      const hc = containerOpts.buildHealthcheck({
        healthcheck: { cmd: 'test', interval: '500ms' },
      });
      expect(hc.Interval).toBe(500 * 1e6);
    });

    it('parses minute duration', () => {
      const hc = containerOpts.buildHealthcheck({
        healthcheck: { cmd: 'test', interval: '2m' },
      });
      expect(hc.Interval).toBe(2 * 60 * 1e9);
    });

    it('defaults to 30s for invalid duration', () => {
      const hc = containerOpts.buildHealthcheck({
        healthcheck: { cmd: 'test', interval: 'invalid' },
      });
      expect(hc.Interval).toBe(30 * 1e9);
    });
  });
});
