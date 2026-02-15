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

const fs = require('fs');
const lockfile = require('proper-lockfile');
const containerManager = require('../src/services/container-manager');
const updateManager = require('../src/services/update-manager');

describe('update-manager', () => {
  let mockRelease;

  beforeEach(() => {
    jest.clearAllMocks();

    // Spy on fs methods (inside beforeEach so restoreAllMocks undoes them)
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);
    jest.spyOn(fs, 'mkdirSync').mockReturnValue(undefined);
    jest.spyOn(fs, 'writeFileSync').mockReturnValue(undefined);

    // Spy on container-manager methods
    jest.spyOn(containerManager, 'pullImage').mockResolvedValue();
    jest.spyOn(containerManager, 'inspectContainer').mockResolvedValue({
      Config: { Image: 'myapp:1.0' },
      Name: '/myapp',
    });
    jest.spyOn(containerManager, 'stopContainer').mockResolvedValue();
    jest.spyOn(containerManager, 'removeContainer').mockResolvedValue();
    jest.spyOn(containerManager, 'createContainer').mockResolvedValue('new-id');

    mockRelease = jest.fn().mockResolvedValue();
    jest.spyOn(lockfile, 'lock').mockResolvedValue(mockRelease);
    updateManager.resetState();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('getUpdateStatus', () => {
    it('returns idle state initially', () => {
      const status = updateManager.getUpdateStatus();
      expect(status).toEqual({
        state: 'idle',
        error: null,
        progress: null,
      });
    });

    it('reflects state changes', async () => {
      // Trigger an update to change state
      const promise = updateManager.triggerUpdate('c1', 'img:2.0');
      await promise;

      const status = updateManager.getUpdateStatus();
      expect(status.state).toBe('completed');
    });
  });

  describe('checkForUpdates', () => {
    it('checks applications from config', async () => {
      const config = {
        applications: [
          { name: 'app1', image: 'app1:latest' },
        ],
      };
      const result = await updateManager.checkForUpdates(config);
      expect(result).toHaveProperty('available');
      expect(result).toHaveProperty('reason');
    });

    it('returns not available when no updates found', async () => {
      const config = { applications: [] };
      const result = await updateManager.checkForUpdates(config);
      expect(result.available).toBe(false);
    });

    it('handles empty applications list', async () => {
      const result = await updateManager.checkForUpdates({});
      expect(result.available).toBe(false);
    });

    it('returns not available when update already in progress', async () => {
      // Complete an update first so state is 'completed' (not idle)
      await updateManager.triggerUpdate('c1', 'img:2.0');

      // Now checkForUpdates should see non-idle state
      const result = await updateManager.checkForUpdates({ applications: [] });
      expect(result.available).toBe(false);
      expect(result.reason).toContain('Update in progress');
    });
  });

  describe('triggerUpdate', () => {
    it('follows full success path: pull -> stop -> remove -> create', async () => {
      await updateManager.triggerUpdate('container1', 'myapp:2.0');

      expect(containerManager.pullImage).toHaveBeenCalledWith('myapp:2.0');
      expect(containerManager.inspectContainer).toHaveBeenCalledWith('container1');
      expect(containerManager.stopContainer).toHaveBeenCalledWith('container1');
      expect(containerManager.removeContainer).toHaveBeenCalledWith('container1');
      expect(containerManager.createContainer).toHaveBeenCalledWith({
        name: 'myapp',
        image: 'myapp:2.0',
        restart_policy: 'always',
      });
    });

    it('acquires and releases lock', async () => {
      await updateManager.triggerUpdate('c1', 'img:2.0');
      expect(lockfile.lock).toHaveBeenCalled();
      expect(mockRelease).toHaveBeenCalled();
    });

    it('transitions through DOWNLOADING -> APPLYING -> VERIFYING -> COMPLETED', async () => {
      const states = [];

      containerManager.pullImage.mockImplementation(async () => {
        states.push(updateManager.getUpdateStatus().state);
      });
      containerManager.stopContainer.mockImplementation(async () => {
        states.push(updateManager.getUpdateStatus().state);
      });

      await updateManager.triggerUpdate('c1', 'img:2.0');

      expect(states).toContain('downloading');
      expect(states).toContain('applying');
      expect(updateManager.getUpdateStatus().state).toBe('completed');
    });

    it('sets state to FAILED on pull error', async () => {
      containerManager.pullImage.mockRejectedValueOnce(new Error('pull failed'));

      await expect(updateManager.triggerUpdate('c1', 'img:2.0')).rejects.toThrow('pull failed');
      expect(updateManager.getUpdateStatus().state).toBe('failed');
      expect(updateManager.getUpdateStatus().error).toBe('pull failed');
    });

    it('throws when not in idle state', async () => {
      // Complete an update to set state to completed
      await updateManager.triggerUpdate('c1', 'img:2.0');

      await expect(updateManager.triggerUpdate('c1', 'img:3.0'))
        .rejects.toThrow('Cannot update while in state: completed');
    });

    it('releases lock even on failure', async () => {
      containerManager.pullImage.mockRejectedValueOnce(new Error('fail'));

      try {
        await updateManager.triggerUpdate('c1', 'img:2.0');
      } catch (_e) {
        // expected
      }

      expect(mockRelease).toHaveBeenCalled();
    });

    it('triggers rollback on stop failure with known old image', async () => {
      containerManager.stopContainer.mockRejectedValueOnce(new Error('stop failed'));

      // For rollback: stopContainer and removeContainer should succeed on second call
      containerManager.stopContainer.mockResolvedValue();
      containerManager.removeContainer.mockResolvedValue();

      await expect(updateManager.triggerUpdate('c1', 'img:2.0')).rejects.toThrow('stop failed');

      // Rollback calls createContainer with the old image
      const rollbackCall = containerManager.createContainer.mock.calls[0];
      expect(rollbackCall[0].image).toBe('myapp:1.0');
    });

    it('handles rollback failure gracefully', async () => {
      containerManager.stopContainer.mockRejectedValueOnce(new Error('stop failed'));
      // Rollback also fails
      containerManager.stopContainer.mockResolvedValue();
      containerManager.removeContainer.mockResolvedValue();
      containerManager.createContainer.mockRejectedValueOnce(new Error('rollback create failed'));

      await expect(updateManager.triggerUpdate('c1', 'img:2.0')).rejects.toThrow('stop failed');
      // Should not throw additional errors from rollback
    });

    it('does not rollback when oldImage is unknown (pull failure)', async () => {
      containerManager.pullImage.mockRejectedValueOnce(new Error('pull failed'));

      await expect(updateManager.triggerUpdate('c1', 'img:2.0')).rejects.toThrow('pull failed');

      // createContainer should not be called since rollback is skipped
      expect(containerManager.createContainer).not.toHaveBeenCalled();
    });

    it('tracks progress through steps', async () => {
      const progresses = [];

      containerManager.pullImage.mockImplementation(async () => {
        progresses.push({ ...updateManager.getUpdateStatus().progress });
      });
      containerManager.stopContainer.mockImplementation(async () => {
        progresses.push({ ...updateManager.getUpdateStatus().progress });
      });

      await updateManager.triggerUpdate('c1', 'img:2.0');

      expect(progresses[0].step).toBe('pulling');
      expect(progresses[1].step).toBe('stopping');
    });
  });

  describe('rollback', () => {
    it('stops, removes, and recreates with old image', async () => {
      await updateManager.rollback('c1', 'myapp:1.0');

      expect(containerManager.stopContainer).toHaveBeenCalled();
      expect(containerManager.removeContainer).toHaveBeenCalledWith('c1', true);
      expect(containerManager.createContainer).toHaveBeenCalledWith({
        name: 'c1',
        image: 'myapp:1.0',
        restart_policy: 'always',
      });
    });

    it('continues even if stop fails during rollback', async () => {
      containerManager.stopContainer.mockRejectedValueOnce(new Error('already stopped'));

      await updateManager.rollback('c1', 'myapp:1.0');
      expect(containerManager.createContainer).toHaveBeenCalled();
    });
  });

  describe('acquireLock', () => {
    it('creates lock file and acquires lock', async () => {
      const release = await updateManager.acquireLock();
      expect(lockfile.lock).toHaveBeenCalled();
      expect(typeof release).toBe('function');
    });

    it('creates lock directory if missing', async () => {
      fs.existsSync.mockReturnValueOnce(false);
      await updateManager.acquireLock();
      expect(fs.mkdirSync).toHaveBeenCalledWith(
        expect.any(String),
        { recursive: true },
      );
    });

    it('creates lock file if missing', async () => {
      fs.existsSync
        .mockReturnValueOnce(true)   // dir exists
        .mockReturnValueOnce(false); // file does not exist
      await updateManager.acquireLock();
      expect(fs.writeFileSync).toHaveBeenCalled();
    });

    it('throws when lock cannot be acquired', async () => {
      lockfile.lock.mockRejectedValueOnce(new Error('lock busy'));
      await expect(updateManager.acquireLock()).rejects.toThrow('lock busy');
    });
  });

  describe('releaseLock', () => {
    it('calls the release function', async () => {
      await updateManager.releaseLock(mockRelease);
      expect(mockRelease).toHaveBeenCalled();
    });

    it('does nothing if release is not a function', async () => {
      await expect(updateManager.releaseLock(null)).resolves.toBeUndefined();
    });
  });

  describe('resetState', () => {
    it('resets state to idle', async () => {
      await updateManager.triggerUpdate('c1', 'img:2.0');
      expect(updateManager.getUpdateStatus().state).toBe('completed');

      updateManager.resetState();
      expect(updateManager.getUpdateStatus().state).toBe('idle');
      expect(updateManager.getUpdateStatus().progress).toBeNull();
    });
  });
});
