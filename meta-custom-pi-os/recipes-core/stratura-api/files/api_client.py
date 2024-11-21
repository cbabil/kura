#!/usr/bin/env python3

import requests
import json
import logging
import os
from typing import Dict, Optional
from datetime import datetime

class DeviceAPIClient:
    def __init__(self):
        self.config_path = '/etc/stratura/api-config.json'
        self.load_config()
        self.setup_session()
        
    def load_config(self):
        with open(self.config_path) as f:
            self.config = json.load(f)
            self.api_url = self.config['api_endpoint']
            self.device_id = self.config['device_id']
            self.api_key = self.config['api_key']
            
    def setup_session(self):
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {self.api_key}',
            'X-Device-ID': self.device_id,
            'Content-Type': 'application/json'
        })
        
    def register_device(self) -> bool:
        """Register device with management platform"""
        try:
            response = self.session.post(
                f"{self.api_url}/devices/register",
                json={
                    'device_id': self.device_id,
                    'hardware_info': self.get_hardware_info(),
                    'software_info': self.get_software_info(),
                    'capabilities': self.get_device_capabilities()
                }
            )
            return response.status_code == 200
        except Exception as e:
            logging.error(f"Device registration failed: {e}")
            return False
            
    def report_status(self):
        """Report device status to management platform"""
        try:
            status = {
                'timestamp': datetime.utcnow().isoformat(),
                'state': self.get_device_state(),
                'metrics': self.get_device_metrics(),
                'containers': self.get_container_status(),
                'network': self.get_network_status(),
                'storage': self.get_storage_status()
            }
            
            response = self.session.post(
                f"{self.api_url}/devices/{self.device_id}/status",
                json=status
            )
            
            if response.status_code != 200:
                logging.error(f"Status report failed: {response.text}")
                
        except Exception as e:
            logging.error(f"Failed to report status: {e}")
            
    def check_updates(self) -> Optional[Dict]:
        """Check for available updates"""
        try:
            response = self.session.get(
                f"{self.api_url}/devices/{self.device_id}/updates"
            )
            
            if response.status_code == 200:
                return response.json()
            return None
            
        except Exception as e:
            logging.error(f"Update check failed: {e}")
            return None
            
    def report_update_status(self, status: Dict):
        """Report update status to management platform"""
        try:
            response = self.session.post(
                f"{self.api_url}/devices/{self.device_id}/updates/status",
                json=status
            )
            
            if response.status_code != 200:
                logging.error(f"Update status report failed: {response.text}")
                
        except Exception as e:
            logging.error(f"Failed to report update status: {e}") 