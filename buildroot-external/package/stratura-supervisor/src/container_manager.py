#!/usr/bin/env python3

import os
import docker
import json
import logging
from typing import Dict, List

class ContainerManager:
    def __init__(self):
        self.client = docker.from_env()
        self.config_path = '/etc/stratura-supervisor/containers.json'
        self.volumes_path = '/var/lib/stratura/volumes'
        
    def load_container_config(self) -> Dict:
        with open(self.config_path, 'r') as f:
            return json.load(f)

    def create_container(self, config: Dict):
        """Create container with enhanced security and monitoring"""
        try:
            # Validate configuration
            self.validate_container_config(config)
            
            # Setup security options
            security_opts = self.setup_container_security(config)
            
            # Setup resource limits
            resources = self.setup_container_resources(config)
            
            # Setup networking
            network = self.setup_container_networking(config)
            
            # Create container
            container = self.client.containers.run(
                image=config['image'],
                name=config['name'],
                detach=True,
                restart_policy={"Name": "always"},
                **security_opts,
                **resources,
                **network,
                labels={
                    'io.stratura.managed': 'true',
                    'io.stratura.app.name': config['name'],
                    'io.stratura.version': config.get('version', 'latest')
                },
                healthcheck=self.setup_healthcheck(config)
            )
            
            # Setup monitoring
            self.setup_container_monitoring(container, config)
            
            return container
            
        except Exception as e:
            logging.error(f"Container creation failed: {e}")
            raise

    def setup_container_security(self, config: Dict) -> Dict:
        """Setup container security options"""
        return {
            'security_opt': [
                'no-new-privileges',
                'seccomp=unconfined' if config.get('privileged', False) else 'seccomp=default',
                f"apparmor={config.get('apparmor_profile', 'stratura-default')}"
            ],
            'cap_drop': ['ALL'],
            'cap_add': config.get('capabilities', []),
            'read_only': config.get('read_only', True)
        }

    def setup_container_monitoring(self, container, config: Dict):
        """Setup container monitoring and alerts"""
        try:
            # Setup resource monitoring
            self.monitor_container_resources(container)
            
            # Setup log monitoring
            self.setup_log_monitoring(container)
            
            # Setup health monitoring
            self.setup_health_monitoring(container)
            
            # Setup alert thresholds
            self.setup_alert_thresholds(container, config)
            
        except Exception as e:
            logging.error(f"Monitoring setup failed: {e}")
            raise

    def prepare_volumes(self, config: Dict) -> Dict:
        volumes = {}
        for volume in config.get('volumes', []):
            host_path = f"{self.volumes_path}/{config['name']}/{volume['name']}"
            os.makedirs(host_path, exist_ok=True)
            volumes[host_path] = {
                'bind': volume['container_path'],
                'mode': volume.get('mode', 'rw')
            }
        return volumes

    def health_check(self) -> List[Dict]:
        status = []
        for container in self.client.containers.list(all=True):
            if container.labels.get('io.stratura.managed'):
                status.append({
                    'name': container.name,
                    'status': container.status,
                    'health': container.attrs['State']['Health']['Status']
                    if 'Health' in container.attrs['State'] else 'unknown'
                })
        return status 

    def prepare_environment(self, config: Dict) -> Dict:
        """Prepare container environment variables"""
        env = {
            'STRATURA_APP_NAME': config['name'],
            'STRATURA_APP_VERSION': config.get('version', 'latest'),
            'STRATURA_DEVICE_ID': os.getenv('STRATURA_DEVICE_ID', 'unknown')
        }
        
        # Add custom environment variables
        env.update(config.get('environment', {}))
        return env

    def setup_container_networking(self, config: Dict):
        """Setup container networking"""
        network_config = config.get('network', {})
        
        if network_config.get('type') == 'host':
            return {'network_mode': 'host'}
        
        network_opts = {
            'network_mode': network_config.get('mode', 'bridge'),
            'ports': network_config.get('ports', {}),
            'dns': network_config.get('dns', []),
            'extra_hosts': network_config.get('extra_hosts', {})
        }
        
        return network_opts

    def setup_container_resources(self, config: Dict):
        """Setup container resource limits"""
        resources = config.get('resources', {})
        
        return {
            'mem_limit': resources.get('memory', '256m'),
            'memswap_limit': resources.get('memory_swap', '-1'),
            'cpu_shares': resources.get('cpu_shares', 1024),
            'cpu_period': resources.get('cpu_period', 100000),
            'cpu_quota': resources.get('cpu_quota', -1)
        }