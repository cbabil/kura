'use strict';

const { LABELS } = require('../../src/utils/constants');

// Shared dockerode mock functions used by container-manager and any test
// that transitively loads it. Defined once so all files share the same
// references, avoiding cache vs mock ordering issues in Bun.

const mockStart = jest.fn().mockResolvedValue();
const mockStop = jest.fn().mockResolvedValue();
const mockRestart = jest.fn().mockResolvedValue();
const mockRemove = jest.fn().mockResolvedValue();
const mockLogs = jest.fn().mockResolvedValue(Buffer.from('log line 1\nlog line 2'));
const mockInspect = jest.fn().mockResolvedValue({
  State: { Status: 'running', Running: true, Health: { Status: 'healthy' } },
  Config: { Image: 'myapp:1.0', Labels: { [LABELS.MANAGED]: 'true' } },
  Name: '/myapp',
});
const mockCreateContainer = jest.fn().mockResolvedValue({
  id: 'new-container-id',
  start: mockStart,
});
const mockListContainers = jest.fn().mockResolvedValue([]);
const mockGetContainer = jest.fn().mockReturnValue({
  start: mockStart,
  stop: mockStop,
  restart: mockRestart,
  remove: mockRemove,
  logs: mockLogs,
  inspect: mockInspect,
});
const mockPull = jest.fn().mockResolvedValue('stream');
const mockFollowProgress = jest.fn().mockImplementation((_stream, cb) => {
  cb(null, [{ status: 'done' }]);
});

// dockerode is CommonJS: require('dockerode') returns the constructor itself.
const dockerodeMockFactory = () => jest.fn().mockImplementation(() => ({
  listContainers: mockListContainers,
  createContainer: mockCreateContainer,
  getContainer: mockGetContainer,
  pull: mockPull,
  modem: { followProgress: mockFollowProgress },
}));

module.exports = {
  mockStart,
  mockStop,
  mockRestart,
  mockRemove,
  mockLogs,
  mockInspect,
  mockCreateContainer,
  mockListContainers,
  mockGetContainer,
  mockPull,
  mockFollowProgress,
  dockerodeMockFactory,
};
