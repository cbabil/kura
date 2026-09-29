'use strict';

const Dockerode = require('dockerode');
const logger = require('../utils/logger');
const { LABELS } = require('../utils/constants');
const opts = require('./container-opts');

const docker = new Dockerode({ socketPath: '/var/run/docker.sock' });
const MANAGED_FILTER = { label: [`${LABELS.MANAGED}=true`] };

async function listContainers(all = true) {
  const containers = await docker.listContainers({ all, filters: MANAGED_FILTER });
  return containers.map((c) => ({
    id: c.Id,
    name: (c.Names[0] || '').replace(/^\//, ''),
    image: c.Image,
    state: c.State,
    status: c.Status,
    labels: c.Labels,
  }));
}

async function createContainer(config) {
  const security = opts.buildSecurityOpts(config);
  const resources = opts.buildResourceOpts(config);
  const networking = opts.buildNetworkOpts(config);
  const healthcheck = opts.buildHealthcheck(config);

  const createOpts = {
    Image: config.image,
    name: config.name,
    Env: opts.buildEnv(config),
    Labels: opts.buildLabels(config),
    HostConfig: {
      RestartPolicy: { Name: config.restart_policy || 'always' },
      Binds: opts.buildBinds(config),
      SecurityOpt: security.securityOpt,
      CapDrop: security.capDrop,
      CapAdd: security.capAdd,
      ReadonlyRootfs: security.readOnly,
      Memory: resources.memory,
      CpuShares: resources.cpuShares,
      NetworkMode: networking.networkMode,
      PortBindings: networking.portBindings,
    },
  };

  if (healthcheck) { createOpts.Healthcheck = healthcheck; }

  const container = await docker.createContainer(createOpts);
  await container.start();
  logger.info({ name: config.name, image: config.image }, 'Container created and started');
  return container.id;
}

/**
 * Returns the container only if the supervisor manages it.
 * Tomo's containers share this Docker daemon; cloud commands must never
 * start, stop, remove or read the logs of containers the supervisor did not
 * create.
 * @param {string} id - Container ID or name
 * @returns {Promise<object>} dockerode container handle
 * @throws {Error} if the container lacks the managed label
 */
async function getManagedContainer(id) {
  const container = docker.getContainer(id);
  const info = await container.inspect();
  if (info?.Config?.Labels?.[LABELS.MANAGED] !== 'true') {
    throw new Error(`Container ${id} is not managed by the supervisor`);
  }
  return container;
}

async function startContainer(id) { await (await getManagedContainer(id)).start(); }
async function stopContainer(id) { await (await getManagedContainer(id)).stop(); }
async function restartContainer(id) { await (await getManagedContainer(id)).restart(); }

async function removeContainer(id, force = false) {
  await (await getManagedContainer(id)).remove({ force });
}

async function getLogs(id, tail = 100) {
  const container = await getManagedContainer(id);
  const logs = await container.logs({ stdout: true, stderr: true, tail });
  return logs.toString('utf8');
}

async function inspectContainer(id) { return docker.getContainer(id).inspect(); }

async function healthCheck() {
  const containers = await docker.listContainers({ all: true, filters: MANAGED_FILTER });
  const results = [];
  for (const c of containers) {
    const name = (c.Names[0] || '').replace(/^\//, '');
    const info = await docker.getContainer(c.Id).inspect();
    const state = info.State || {};
    results.push({
      name,
      status: state.Status || 'unknown',
      health: state.Health ? state.Health.Status : 'unknown',
      running: state.Running || false,
    });
  }
  return results;
}

async function pullImage(image) {
  const stream = await docker.pull(image);
  return new Promise((resolve, reject) => {
    docker.modem.followProgress(stream, (err, output) => {
      if (err) { return reject(err); }
      logger.info({ image }, 'Image pulled');
      resolve(output);
    });
  });
}

module.exports = {
  getManagedContainer,
  listContainers,
  createContainer,
  startContainer,
  stopContainer,
  restartContainer,
  removeContainer,
  getLogs,
  inspectContainer,
  healthCheck,
  pullImage,
};
