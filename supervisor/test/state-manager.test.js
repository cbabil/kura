'use strict';

jest.mock('../src/utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
  debug: jest.fn(),
}));

const fs = require('fs');
const lockfile = require('proper-lockfile');

const stateManager = require('../src/services/state-manager');

describe('state-manager', () => {
  let mockRelease;

  beforeEach(() => {
    jest.clearAllMocks();

    // Spy on fs methods (inside beforeEach so restoreAllMocks undoes them)
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);
    jest.spyOn(fs, 'mkdirSync').mockReturnValue(undefined);
    jest.spyOn(fs, 'readFileSync');
    jest.spyOn(fs, 'writeFileSync').mockReturnValue(undefined);
    jest.spyOn(fs, 'renameSync').mockReturnValue(undefined);

    mockRelease = jest.fn().mockResolvedValue();
    jest.spyOn(lockfile, 'lock').mockResolvedValue(mockRelease);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('getDefaultState', () => {
    it('returns all required fields', () => {
      const state = stateManager.getDefaultState();
      expect(state).toHaveProperty('version', '0.0.1');
      expect(state).toHaveProperty('boot_count', 0);
      expect(state).toHaveProperty('last_boot', null);
      expect(state).toHaveProperty('update_status');
      expect(state).toHaveProperty('network_status');
      expect(state).toHaveProperty('containers');
      expect(state).toHaveProperty('provisioning');
    });

    it('has provisioning set to incomplete by default', () => {
      const state = stateManager.getDefaultState();
      expect(state.provisioning).toEqual({ completed: false, timestamp: null });
    });

    it('has empty containers object', () => {
      const state = stateManager.getDefaultState();
      expect(state.containers).toEqual({});
    });

    it('has idle update_state', () => {
      const state = stateManager.getDefaultState();
      expect(state.update_status.update_state).toBe('idle');
    });
  });

  describe('load', () => {
    it('reads and parses state file', async () => {
      const mockState = { ...stateManager.getDefaultState(), boot_count: 5 };
      fs.readFileSync.mockReturnValueOnce(JSON.stringify(mockState));

      const result = await stateManager.load();
      expect(result.boot_count).toBe(5);
      expect(lockfile.lock).toHaveBeenCalled();
    });

    it('returns default state when file does not exist', async () => {
      fs.existsSync
        .mockReturnValueOnce(true)   // ensureDir - STATE_DIR exists
        .mockReturnValueOnce(false); // STATE_FILE does not exist

      const result = await stateManager.load();
      expect(result.boot_count).toBe(0);
      expect(result.version).toBe('0.0.1');
    });

    it('returns default state on corrupted JSON', async () => {
      fs.readFileSync.mockReturnValueOnce('{ invalid json !!!');

      const result = await stateManager.load();
      expect(result).toEqual(stateManager.getDefaultState());
    });

    it('releases lock after reading', async () => {
      fs.readFileSync.mockReturnValueOnce(JSON.stringify(stateManager.getDefaultState()));
      await stateManager.load();
      expect(mockRelease).toHaveBeenCalled();
    });

    it('returns default state on lock failure', async () => {
      lockfile.lock.mockRejectedValueOnce(new Error('lock busy'));
      const result = await stateManager.load();
      expect(result).toEqual(stateManager.getDefaultState());
    });
  });

  describe('save', () => {
    it('writes atomically via tmp file then rename', async () => {
      const state = stateManager.getDefaultState();
      await stateManager.save(state);

      expect(fs.writeFileSync).toHaveBeenCalledWith(
        expect.stringContaining('.tmp'),
        JSON.stringify(state, null, 2),
      );
      expect(fs.renameSync).toHaveBeenCalled();
    });

    it('acquires lock before writing', async () => {
      const state = stateManager.getDefaultState();
      await stateManager.save(state);
      expect(lockfile.lock).toHaveBeenCalled();
    });

    it('releases lock after writing', async () => {
      const state = stateManager.getDefaultState();
      await stateManager.save(state);
      expect(mockRelease).toHaveBeenCalled();
    });

    it('writes directly when state file does not exist', async () => {
      fs.existsSync
        .mockReturnValueOnce(true)   // ensureDir - STATE_DIR exists
        .mockReturnValueOnce(false); // STATE_FILE does not exist

      const state = stateManager.getDefaultState();
      await stateManager.save(state);

      expect(fs.writeFileSync).toHaveBeenCalledWith(
        expect.not.stringContaining('.tmp'),
        JSON.stringify(state, null, 2),
      );
      expect(lockfile.lock).not.toHaveBeenCalled();
    });

    it('throws on write failure', async () => {
      // writeFileSync is called inside withLock for the tmp file
      fs.writeFileSync.mockImplementationOnce(() => {
        throw new Error('disk full');
      });

      await expect(stateManager.save(stateManager.getDefaultState()))
        .rejects.toThrow('disk full');
    });
  });

  describe('updateBootCount', () => {
    it('increments boot count', async () => {
      const baseState = { ...stateManager.getDefaultState(), boot_count: 3 };
      fs.readFileSync.mockReturnValue(JSON.stringify(baseState));

      const result = await stateManager.updateBootCount();
      expect(result.boot_count).toBe(4);
    });

    it('sets last_boot to ISO timestamp', async () => {
      fs.readFileSync.mockReturnValue(JSON.stringify(stateManager.getDefaultState()));

      const result = await stateManager.updateBootCount();
      expect(result.last_boot).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });

  describe('updateNetworkStatus', () => {
    it('updates nested network_status object', async () => {
      fs.readFileSync.mockReturnValue(JSON.stringify(stateManager.getDefaultState()));

      const result = await stateManager.updateNetworkStatus({
        connected: true,
        ip_address: '192.168.1.100',
      });

      expect(result.network_status.connected).toBe(true);
      expect(result.network_status.ip_address).toBe('192.168.1.100');
    });

    it('merges with existing network status', async () => {
      const existing = stateManager.getDefaultState();
      existing.network_status.interface = 'eth0';
      fs.readFileSync.mockReturnValue(JSON.stringify(existing));

      const result = await stateManager.updateNetworkStatus({ connected: true });
      expect(result.network_status.interface).toBe('eth0');
      expect(result.network_status.connected).toBe(true);
    });
  });

  describe('updateContainerStatus', () => {
    it('adds new container entry', async () => {
      fs.readFileSync.mockReturnValue(JSON.stringify(stateManager.getDefaultState()));

      const result = await stateManager.updateContainerStatus('myapp', {
        status: 'running',
        image: 'myapp:latest',
      });

      expect(result.containers.myapp).toEqual({
        status: 'running',
        image: 'myapp:latest',
      });
    });

    it('updates existing container entry', async () => {
      const existing = stateManager.getDefaultState();
      existing.containers.myapp = { status: 'running', image: 'myapp:1.0' };
      fs.readFileSync.mockReturnValue(JSON.stringify(existing));

      const result = await stateManager.updateContainerStatus('myapp', {
        status: 'stopped',
        image: 'myapp:2.0',
      });

      expect(result.containers.myapp.status).toBe('stopped');
      expect(result.containers.myapp.image).toBe('myapp:2.0');
    });
  });

  describe('setProvisioningComplete', () => {
    it('sets completed flag to true', async () => {
      fs.readFileSync.mockReturnValue(JSON.stringify(stateManager.getDefaultState()));
      const result = await stateManager.setProvisioningComplete();
      expect(result.provisioning.completed).toBe(true);
    });

    it('sets timestamp to ISO string', async () => {
      fs.readFileSync.mockReturnValue(JSON.stringify(stateManager.getDefaultState()));
      const result = await stateManager.setProvisioningComplete();
      expect(result.provisioning.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });
});
