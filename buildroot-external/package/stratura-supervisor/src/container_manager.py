#!/usr/bin/env python3

import os
import json
import logging
import subprocess
from typing import Dict, List, Optional

logger = logging.getLogger('stratura-container-manager')


class DockerCLI:
    """Docker operations via CLI subprocess calls"""

    @staticmethod
    def run_cmd(cmd: list, check: bool = True) -> subprocess.CompletedProcess:
        """Run docker command and return result"""
        full_cmd = ['docker'] + cmd
        try:
            result = subprocess.run(
                full_cmd,
                capture_output=True,
                text=True,
                check=check
            )
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f"Docker command failed: {' '.join(full_cmd)}")
            logger.error(f"stderr: {e.stderr}")
            raise

    @staticmethod
    def inspect(name: str) -> Optional[Dict]:
        """Inspect container and return JSON data"""
        result = DockerCLI.run_cmd(['inspect', name], check=False)
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return data[0] if data else None
        return None


class ContainerManager:
    def __init__(self):
        self.config_path = '/etc/stratura/containers.json'
        self.volumes_path = '/var/lib/stratura/volumes'

    def load_container_config(self) -> Dict:
        try:
            with open(self.config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.warning(f"Container config not found at {self.config_path}")
            return {'containers': []}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid container config JSON: {e}")
            return {'containers': []}

    def validate_container_config(self, config: Dict) -> bool:
        """Validate container configuration"""
        required = ['name', 'image']
        for field in required:
            if field not in config:
                logger.error(f"Missing required field: {field}")
                return False
        return True

    def create_container(self, config: Dict) -> bool:
        """Create container with enhanced security and monitoring"""
        try:
            if not self.validate_container_config(config):
                return False

            cmd = ['run', '-d', '--name', config['name']]

            # Restart policy
            cmd.extend(['--restart', config.get('restart_policy', 'always')])

            # Security options
            security_opts = self.setup_container_security(config)
            for opt in security_opts.get('security_opt', []):
                cmd.extend(['--security-opt', opt])

            # Cap drop/add
            for cap in security_opts.get('cap_drop', []):
                cmd.extend(['--cap-drop', cap])
            for cap in security_opts.get('cap_add', []):
                cmd.extend(['--cap-add', cap])

            # Read-only filesystem
            if security_opts.get('read_only', False):
                cmd.append('--read-only')

            # Resource limits
            resources = self.setup_container_resources(config)
            if resources.get('mem_limit'):
                cmd.extend(['-m', resources['mem_limit']])
            if resources.get('cpu_shares'):
                cmd.extend(['--cpu-shares', str(resources['cpu_shares'])])

            # Networking
            network = self.setup_container_networking(config)
            if network.get('network_mode'):
                cmd.extend(['--network', network['network_mode']])
            for port_mapping in network.get('ports', []):
                cmd.extend(['-p', port_mapping])

            # Environment
            env = self.prepare_environment(config)
            for key, value in env.items():
                cmd.extend(['-e', f'{key}={value}'])

            # Volumes
            volumes = self.prepare_volumes(config)
            for host_path, mount_info in volumes.items():
                bind = mount_info['bind']
                mode = mount_info.get('mode', 'rw')
                cmd.extend(['-v', f'{host_path}:{bind}:{mode}'])

            # Labels
            labels = {
                'io.stratura.managed': 'true',
                'io.stratura.app.name': config['name'],
                'io.stratura.version': config.get('version', 'latest')
            }
            for key, value in labels.items():
                cmd.extend(['--label', f'{key}={value}'])

            # Healthcheck
            healthcheck = config.get('healthcheck', {})
            if healthcheck.get('cmd'):
                cmd.extend(['--health-cmd', healthcheck['cmd']])
                if healthcheck.get('interval'):
                    cmd.extend(['--health-interval', healthcheck['interval']])
                if healthcheck.get('timeout'):
                    cmd.extend(['--health-timeout', healthcheck['timeout']])
                if healthcheck.get('retries'):
                    cmd.extend(['--health-retries', str(healthcheck['retries'])])

            # Image
            cmd.append(config['image'])

            # Run command
            DockerCLI.run_cmd(cmd)
            logger.info(f"Container {config['name']} created successfully")
            return True

        except Exception as e:
            logger.error(f"Container creation failed: {e}")
            return False

    def setup_container_security(self, config: Dict) -> Dict:
        """Setup container security options"""
        privileged = config.get('privileged', False)
        seccomp = 'unconfined' if privileged else 'default'

        return {
            'security_opt': [
                'no-new-privileges',
                f'seccomp={seccomp}'
            ],
            'cap_drop': ['ALL'],
            'cap_add': config.get('capabilities', []),
            'read_only': config.get('read_only', False)
        }

    def setup_container_resources(self, config: Dict) -> Dict:
        """Setup container resource limits"""
        resources = config.get('resources', {})
        return {
            'mem_limit': resources.get('memory', '256m'),
            'cpu_shares': resources.get('cpu_shares', 1024)
        }

    def setup_container_networking(self, config: Dict) -> Dict:
        """Setup container networking"""
        network_config = config.get('network', {})

        if network_config.get('type') == 'host':
            return {'network_mode': 'host', 'ports': []}

        ports = []
        for port_config in network_config.get('ports', []):
            if isinstance(port_config, str):
                ports.append(port_config)
            elif isinstance(port_config, dict):
                host = port_config.get('host', '')
                container = port_config.get('container', '')
                protocol = port_config.get('protocol', 'tcp')
                ports.append(f'{host}:{container}/{protocol}')

        return {
            'network_mode': network_config.get('mode', 'bridge'),
            'ports': ports
        }

    def prepare_environment(self, config: Dict) -> Dict:
        """Prepare container environment variables"""
        env = {
            'STRATURA_APP_NAME': config['name'],
            'STRATURA_APP_VERSION': config.get('version', 'latest'),
            'STRATURA_DEVICE_ID': os.getenv('STRATURA_DEVICE_ID', 'unknown')
        }
        env.update(config.get('environment', {}))
        return env

    def prepare_volumes(self, config: Dict) -> Dict:
        """Prepare container volumes"""
        volumes = {}
        for volume in config.get('volumes', []):
            if isinstance(volume, str):
                # Simple volume string like "/host:/container"
                parts = volume.split(':')
                if len(parts) >= 2:
                    volumes[parts[0]] = {
                        'bind': parts[1],
                        'mode': parts[2] if len(parts) > 2 else 'rw'
                    }
            elif isinstance(volume, dict):
                host_path = volume.get('host_path')
                if not host_path:
                    host_path = f"{self.volumes_path}/{config['name']}/{volume['name']}"
                os.makedirs(host_path, exist_ok=True)
                volumes[host_path] = {
                    'bind': volume['container_path'],
                    'mode': volume.get('mode', 'rw')
                }
        return volumes

    def health_check(self) -> List[Dict]:
        """Get health status of all managed containers"""
        status = []

        # List all containers with stratura label
        result = DockerCLI.run_cmd([
            'ps', '-a',
            '--filter', 'label=io.stratura.managed=true',
            '--format', '{{.Names}}'
        ], check=False)

        if result.returncode != 0:
            return status

        container_names = [n for n in result.stdout.strip().split('\n') if n]

        for name in container_names:
            info = DockerCLI.inspect(name)
            if info:
                state = info.get('State', {})
                health = 'unknown'
                if 'Health' in state:
                    health = state['Health'].get('Status', 'unknown')

                status.append({
                    'name': name,
                    'status': state.get('Status', 'unknown'),
                    'health': health,
                    'running': state.get('Running', False)
                })

        return status

    def stop_container(self, name: str) -> bool:
        """Stop a container"""
        try:
            DockerCLI.run_cmd(['stop', name])
            return True
        except Exception as e:
            logger.error(f"Failed to stop container {name}: {e}")
            return False

    def remove_container(self, name: str, force: bool = False) -> bool:
        """Remove a container"""
        try:
            cmd = ['rm']
            if force:
                cmd.append('-f')
            cmd.append(name)
            DockerCLI.run_cmd(cmd)
            return True
        except Exception as e:
            logger.error(f"Failed to remove container {name}: {e}")
            return False

    def get_logs(self, name: str, tail: int = 100) -> str:
        """Get container logs"""
        try:
            result = DockerCLI.run_cmd(['logs', '--tail', str(tail), name])
            return result.stdout + result.stderr
        except Exception as e:
            logger.error(f"Failed to get logs for {name}: {e}")
            return ""
