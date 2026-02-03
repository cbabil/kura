#!/usr/bin/env python3

import json
import logging
import os
from typing import Dict, Optional
from datetime import datetime
from stratura.state import DeviceStateManager
from stratura.api import DeviceAPIClient
from stratura.network import NetworkManager
from stratura.containers import ContainerManager

class ProvisioningManager:
    def __init__(self):
        self.config_path = '/etc/stratura/provisioning-config.json'
        self.state_manager = DeviceStateManager()
        self.api_client = DeviceAPIClient()
        self.load_config()
        
    def load_config(self):
        with open(self.config_path) as f:
            self.config = json.load(f)
            
    def provision_device(self) -> bool:
        """Run device provisioning workflow"""
        try:
            # Check if already provisioned
            if self.state_manager.state['provisioning']['completed']:
                logging.info("Device already provisioned")
                return True
                
            # Generate device identity
            if not self.generate_device_identity():
                raise Exception("Failed to generate device identity")
                
            # Register with management platform
            if not self.api_client.register_device():
                raise Exception("Failed to register device")
                
            # Configure networking
            if not self.configure_networking():
                raise Exception("Failed to configure networking")
                
            # Setup containers
            if not self.setup_containers():
                raise Exception("Failed to setup containers")
                
            # Configure monitoring
            if not self.configure_monitoring():
                raise Exception("Failed to configure monitoring")
                
            # Mark provisioning complete
            self.state_manager.set_provisioning_complete()
            
            return True
            
        except Exception as e:
            logging.error(f"Device provisioning failed: {e}")
            return False
            
    def generate_device_identity(self) -> bool:
        """Generate unique device identity"""
        try:
            # Generate device certificates
            self.generate_device_certificates()
            
            # Generate device ID
            device_id = self.generate_device_id()
            
            # Save identity configuration
            self.save_identity_config(device_id)
            
            return True
            
        except Exception as e:
            logging.error(f"Failed to generate device identity: {e}")
            return False
            
    def configure_networking(self) -> bool:
        """Configure device networking"""
        try:
            network_manager = NetworkManager()
            
            # Configure primary network
            network_manager.setup_network(self.config['network'])
            
            # Configure failover if enabled
            if self.config['network'].get('failover', {}).get('enabled'):
                network_manager.setup_failover(
                    self.config['network']['failover']
                )
                
            # Wait for connectivity
            if not network_manager.wait_for_connectivity(timeout=300):
                raise Exception("Failed to establish network connectivity")
                
            return True
            
        except Exception as e:
            logging.error(f"Network configuration failed: {e}")
            return False
            
    def setup_containers(self) -> bool:
        """Setup application containers"""
        try:
            container_manager = ContainerManager()
            
            # Pull container images
            for container in self.config['containers']:
                if not container_manager.pull_image(container['image']):
                    raise Exception(f"Failed to pull image: {container['image']}")
                    
            # Create and start containers
            for container in self.config['containers']:
                if not container_manager.create_container(container):
                    raise Exception(f"Failed to create container: {container['name']}")
                    
            return True
            
        except Exception as e:
            logging.error(f"Container setup failed: {e}")
            return False 