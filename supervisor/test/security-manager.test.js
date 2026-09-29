'use strict';

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const config = require('../src/config');
const securityManager = require('../src/services/security-manager');

describe('security-manager', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    securityManager._resetConfig();
    jest.spyOn(config, 'loadSecurityConfig').mockReturnValue({
      container_security: {
        verify_signatures: true,
        allowed_registries: ['registry.kura.io', 'docker.io'],
        seccomp_profile: 'default',
      },
      update_security: {
        verify_signatures: true,
        require_chain_of_trust: true,
        rollback_protection: true,
      },
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('getSecurityOpts', () => {
    it('returns no-new-privileges and default seccomp for non-privileged', () => {
      const opts = securityManager.getSecurityOpts({ name: 'test' });
      expect(opts.securityOpt).toContain('no-new-privileges');
      expect(opts.securityOpt).toContain('seccomp=default');
      expect(opts.capDrop).toEqual(['ALL']);
    });

    it('returns seccomp=unconfined for privileged', () => {
      const opts = securityManager.getSecurityOpts({ privileged: true });
      expect(opts.securityOpt).toContain('seccomp=unconfined');
    });

    it('includes capabilities from config', () => {
      const opts = securityManager.getSecurityOpts({ capabilities: ['NET_BIND_SERVICE'] });
      expect(opts.capAdd).toEqual(['NET_BIND_SERVICE']);
    });

    it('sets readOnly from config', () => {
      const opts = securityManager.getSecurityOpts({ read_only: true });
      expect(opts.readOnly).toBe(true);
    });
  });

  describe('validateImage', () => {
    it('validates allowed registry', () => {
      const result = securityManager.validateImage('registry.kura.io/app:1.0');
      expect(result.valid).toBe(true);
    });

    it('validates docker.io short form', () => {
      const result = securityManager.validateImage('nginx:latest');
      expect(result.valid).toBe(true);
    });

    it('validates docker.io with user prefix', () => {
      const result = securityManager.validateImage('user/app:1.0');
      expect(result.valid).toBe(true);
    });

    it('rejects disallowed registry', () => {
      const result = securityManager.validateImage('evil.io/app:1.0');
      expect(result.valid).toBe(false);
      expect(result.reason).toContain('not in allowed list');
    });

    it('allows when signature verification disabled', () => {
      securityManager._resetConfig();
      config.loadSecurityConfig.mockReturnValueOnce({
        container_security: {
          verify_signatures: false,
          allowed_registries: [],
        },
      });
      const result = securityManager.validateImage('any.registry/app:1.0');
      expect(result.valid).toBe(true);
    });
  });

  describe('auditContainerSecurity', () => {
    it('flags privileged mode as critical', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: { Privileged: true },
      });
      expect(findings).toContainEqual(
        expect.objectContaining({ severity: 'critical', issue: expect.stringContaining('privileged') }),
      );
    });

    it('flags host network as warning', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: { NetworkMode: 'host' },
      });
      expect(findings).toContainEqual(
        expect.objectContaining({ severity: 'warning', issue: expect.stringContaining('host network') }),
      );
    });

    it('flags host PID namespace as critical', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: { PidMode: 'host' },
      });
      expect(findings).toContainEqual(
        expect.objectContaining({ severity: 'critical', issue: expect.stringContaining('PID') }),
      );
    });

    it('flags missing no-new-privileges', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: { SecurityOpt: [] },
      });
      expect(findings).toContainEqual(
        expect.objectContaining({ issue: expect.stringContaining('no-new-privileges') }),
      );
    });

    it('flags dangerous capabilities', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: { CapAdd: ['SYS_ADMIN', 'NET_ADMIN'] },
      });
      expect(findings).toContainEqual(
        expect.objectContaining({ issue: expect.stringContaining('SYS_ADMIN') }),
      );
      expect(findings).toContainEqual(
        expect.objectContaining({ issue: expect.stringContaining('NET_ADMIN') }),
      );
    });

    it('flags writable root filesystem', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: { ReadonlyRootfs: false },
      });
      expect(findings).toContainEqual(
        expect.objectContaining({ severity: 'info', issue: expect.stringContaining('writable') }),
      );
    });

    it('flags no memory limit', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: { Memory: 0 },
      });
      expect(findings).toContainEqual(
        expect.objectContaining({ issue: expect.stringContaining('memory limit') }),
      );
    });

    it('returns no findings for secure container', () => {
      const findings = securityManager.auditContainerSecurity({
        Name: '/test',
        HostConfig: {
          Privileged: false,
          NetworkMode: 'bridge',
          PidMode: '',
          SecurityOpt: ['no-new-privileges'],
          CapAdd: [],
          ReadonlyRootfs: true,
          Memory: 256 * 1024 * 1024,
        },
      });
      expect(findings).toEqual([]);
    });
  });
});
