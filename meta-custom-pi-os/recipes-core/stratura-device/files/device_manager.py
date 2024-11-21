#!/usr/bin/env python3

import json
import os
import logging
import subprocess
from typing import Dict, List
from datetime import datetime
import dbus
from stratura.network import NetworkManager
from stratura.containers import ContainerManager

class DeviceManager:
    def __init__(self):
        self.config_path = '/etc/stratura/device-config.json'
        self.state_path = '/var/lib/stratura/device-state.json'
        self.load_config()
        
    def load_config(self):
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
            
    def get_device_info(self) -> Dict:
        """Get comprehensive device information"""
        try:
            info = {
                'device_id': self.get_device_id(),
                'hardware': self.get_hardware_info(),
                'software': self.get_software_info(),
                'network': self.get_network_info(),
                'storage': self.get_storage_info(),
                'containers': self.get_container_info(),
                'timestamp': datetime.utcnow().isoformat()
            }
            return info
        except Exception as e:
            logging.error(f"Failed to get device info: {e}")
            raise

    def get_hardware_info(self) -> Dict:
        """Get hardware information"""
        try:
            cpu_info = self.get_cpu_info()
            memory_info = self.get_memory_info()
            disk_info = self.get_disk_info()
            
            return {
                'model': 'Raspberry Pi 5',
                'serial': self.get_device_serial(),
                'cpu': cpu_info,
                'memory': memory_info,
                'storage': disk_info,
                'temperature': self.get_temperature()
            }
        except Exception as e:
            logging.error(f"Failed to get hardware info: {e}")
            raise

    def get_software_info(self) -> Dict:
        """Get software versions and states"""
        try:
            return {
                'os_version': self.get_os_version(),
                'kernel': self.get_kernel_version(),
                'bootloader': self.get_bootloader_version(),
                'docker': self.get_docker_version(),
                'supervisor': self.get_supervisor_version(),
                'updates': self.get_update_status()
            }
        except Exception as e:
            logging.error(f"Failed to get software info: {e}")
            raise

    def provision_device(self, config: Dict):
        """Provision device with new configuration"""
        try:
            # Validate configuration
            self.validate_config(config)
            
            # Apply network configuration
            self.configure_network(config.get('network', {}))
            
            # Setup containers
            self.setup_containers(config.get('containers', []))
            
            # Configure device settings
            self.configure_device(config.get('device', {}))
            
            # Save configuration
            self.save_config(config)
            
            return True
        except Exception as e:
            logging.error(f"Device provisioning failed: {e}")
            raise

    def configure_network(self, config: Dict):
        """Configure network settings"""
        try:
            nm = NetworkManager()
            nm.setup_network(config)
            
            # Configure VPN if enabled
            if config.get('vpn', {}).get('enabled', False):
                self.setup_vpn(config['vpn'])
                
            # Configure firewall
            self.configure_firewall(config.get('firewall', {}))
            
        except Exception as e:
            logging.error(f"Network configuration failed: {e}")
            raise

    def setup_containers(self, containers: List[Dict]):
        """Setup application containers"""
        try:
            container_manager = ContainerManager()
            
            for container in containers:
                # Validate container config
                self.validate_container_config(container)
                
                # Pull container image
                container_manager.pull_image(container['image'])
                
                # Create and start container
                container_manager.create_container(container)
                
        except Exception as e:
            logging.error(f"Container setup failed: {e}")
            raise

    def configure_device(self, config: Dict):
        """Configure device-specific settings"""
        try:
            # Set hostname
            if 'hostname' in config:
                self.set_hostname(config['hostname'])
                
            # Configure timezone
            if 'timezone' in config:
                self.set_timezone(config['timezone'])
                
            # Setup logging
            if 'logging' in config:
                self.configure_logging(config['logging'])
                
            # Configure monitoring
            if 'monitoring' in config:
                self.setup_monitoring(config['monitoring'])
                
        except Exception as e:
            logging.error(f"Device configuration failed: {e}")
            raise

    def get_device_metrics(self) -> Dict:
        """Get current device metrics"""
        try:
            return {
                'cpu_usage': self.get_cpu_usage(),
                'memory_usage': self.get_memory_usage(),
                'disk_usage': self.get_disk_usage(),
                'network_stats': self.get_network_stats(),
                'container_stats': self.get_container_stats(),
                'temperature': self.get_temperature(),
                'timestamp': datetime.utcnow().isoformat()
            }
        except Exception as e:
            logging.error(f"Failed to get device metrics: {e}")
            raise

    def validate_config(self, config: Dict):
        """Validate device configuration"""
        required_fields = ['device', 'network', 'containers']
        for field in required_fields:
            if field not in config:
                raise ValueError(f"Missing required configuration: {field}")
                
        # Validate network config
        if 'network' in config:
            self.validate_network_config(config['network'])
            
        # Validate container configs
        if 'containers' in config:
            for container in config['containers']:
                self.validate_container_config(container) 