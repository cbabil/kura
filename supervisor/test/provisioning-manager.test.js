'use strict';

const { dockerodeMockFactory } = require('./helpers/dockerode-mock');
jest.mock('dockerode', dockerodeMockFactory);

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const stateManager = require('../src/services/state-manager');
const containerManager = require('../src/services/container-manager');
const securityManager = require('../src/services/security-manager');
const provisioningManager = require('../src/services/provisioning-manager');

describe('provisioning-manager', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    jest.spyOn(stateManager, 'load').mockResolvedValue({
      provisioning: { completed: false, timestamp: null },
    });
    jest.spyOn(stateManager, 'save').mockResolvedValue();
    jest.spyOn(stateManager, 'setProvisioningComplete').mockResolvedValue();
    jest.spyOn(stateManager, 'updateContainerStatus').mockResolvedValue();

    jest.spyOn(containerManager, 'pullImage').mockResolvedValue();
    jest.spyOn(containerManager, 'createContainer').mockResolvedValue('container-id');

    jest.spyOn(securityManager, 'validateImage').mockReturnValue({ valid: true, reason: 'ok' });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('isProvisioned', () => {
    it('returns false on fresh state', async () => {
      stateManager.load.mockResolvedValueOnce({
        provisioning: { completed: false, timestamp: null },
      });

      const result = await provisioningManager.isProvisioned();
      expect(result).toBe(false);
    });

    it('returns true after provisioning is complete', async () => {
      stateManager.load.mockResolvedValueOnce({
        provisioning: { completed: true, timestamp: '2025-01-01T00:00:00.000Z' },
      });

      const result = await provisioningManager.isProvisioned();
      expect(result).toBe(true);
    });
  });

  describe('provision', () => {
    it('provisions containers in order', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: false, timestamp: null },
      });

      const config = {
        applications: [
          { name: 'app1', image: 'registry.kura.io/app1:1.0' },
          { name: 'app2', image: 'registry.kura.io/app2:1.0' },
        ],
      };

      const result = await provisioningManager.provision(config);

      expect(result).toBe(true);
      expect(containerManager.pullImage).toHaveBeenCalledTimes(2);
      expect(containerManager.createContainer).toHaveBeenCalledTimes(2);
      expect(stateManager.setProvisioningComplete).toHaveBeenCalled();
    });

    it('calls pullImage before createContainer for each app', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: false, timestamp: null },
      });

      const callOrder = [];
      containerManager.pullImage.mockImplementation(async () => {
        callOrder.push('pull');
      });
      containerManager.createContainer.mockImplementation(async () => {
        callOrder.push('create');
        return 'id';
      });

      const config = {
        applications: [{ name: 'app1', image: 'app1:1.0' }],
      };

      await provisioningManager.provision(config);
      expect(callOrder).toEqual(['pull', 'create']);
    });

    it('skips if already provisioned', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: true, timestamp: '2025-01-01T00:00:00.000Z' },
      });

      const result = await provisioningManager.provision({ applications: [{ name: 'a', image: 'b' }] });

      expect(result).toBe(true);
      expect(containerManager.pullImage).not.toHaveBeenCalled();
      expect(containerManager.createContainer).not.toHaveBeenCalled();
    });

    it('returns false on container setup failure', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: false, timestamp: null },
      });
      containerManager.pullImage.mockRejectedValueOnce(new Error('pull failed'));

      const result = await provisioningManager.provision({
        applications: [{ name: 'app1', image: 'app1:1.0' }],
      });

      expect(result).toBe(false);
      expect(stateManager.setProvisioningComplete).not.toHaveBeenCalled();
    });

    it('skips apps with missing name or image', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: false, timestamp: null },
      });

      const config = {
        applications: [
          { name: '', image: 'img:1' },
          { image: 'img:2' },
          { name: 'valid', image: 'img:3' },
        ],
      };

      await provisioningManager.provision(config);
      // Only the valid app should be processed
      expect(containerManager.pullImage).toHaveBeenCalledTimes(1);
      expect(containerManager.pullImage).toHaveBeenCalledWith('img:3');
    });

    it('skips apps that fail image validation', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: false, timestamp: null },
      });
      securityManager.validateImage
        .mockReturnValueOnce({ valid: false, reason: 'disallowed registry' })
        .mockReturnValueOnce({ valid: true, reason: 'ok' });

      const config = {
        applications: [
          { name: 'bad', image: 'evil.io/app:1' },
          { name: 'good', image: 'registry.kura.io/app:1' },
        ],
      };

      await provisioningManager.provision(config);
      expect(containerManager.pullImage).toHaveBeenCalledTimes(1);
      expect(containerManager.pullImage).toHaveBeenCalledWith('registry.kura.io/app:1');
    });

    it('updates container status after successful setup', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: false, timestamp: null },
      });

      await provisioningManager.provision({
        applications: [{ name: 'app1', image: 'app1:1.0' }],
      });

      expect(stateManager.updateContainerStatus).toHaveBeenCalledWith(
        'app1',
        expect.objectContaining({
          status: 'running',
          image: 'app1:1.0',
        }),
      );
    });

    it('provisions with empty applications list', async () => {
      stateManager.load.mockResolvedValue({
        provisioning: { completed: false, timestamp: null },
      });

      const result = await provisioningManager.provision({ applications: [] });
      expect(result).toBe(true);
      expect(stateManager.setProvisioningComplete).toHaveBeenCalled();
    });
  });
});
