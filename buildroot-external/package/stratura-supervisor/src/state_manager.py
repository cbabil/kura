#!/usr/bin/env python3

import json
import os
import logging
from typing import Dict, Optional
from datetime import datetime
import fcntl

class DeviceStateManager:
    def __init__(self):
        self.state_file = '/var/lib/stratura/device-state.json'
        self.state_lock = '/var/lock/stratura-state.lock'
        self.load_state()
        
    def load_state(self):
        """Load device state with file locking"""
        try:
            with open(self.state_lock, 'w') as lock:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
                
                if os.path.exists(self.state_file):
                    with open(self.state_file, 'r') as f:
                        self.state = json.load(f)
                else:
                    self.state = self.get_default_state()
                    self.save_state()
                    
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
                
        except Exception as e:
            logging.error(f"Failed to load state: {e}")
            self.state = self.get_default_state()
            
    def save_state(self):
        """Save device state with file locking"""
        try:
            with open(self.state_lock, 'w') as lock:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
                
                with open(self.state_file, 'w') as f:
                    json.dump(self.state, f, indent=2)
                    
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
                
        except Exception as e:
            logging.error(f"Failed to save state: {e}")
            
    def get_default_state(self) -> Dict:
        """Get default device state"""
        return {
            'version': '0.0.1',
            'boot_count': 0,
            'last_boot': None,
            'update_status': {
                'last_update': None,
                'current_version': '0.0.1',
                'update_state': 'idle'
            },
            'network_status': {
                'connected': False,
                'interface': None,
                'ip_address': None
            },
            'containers': {},
            'provisioning': {
                'completed': False,
                'timestamp': None
            }
        }
        
    def update_boot_count(self):
        """Update boot count and timestamp"""
        self.state['boot_count'] += 1
        self.state['last_boot'] = datetime.utcnow().isoformat()
        self.save_state()
        
    def update_network_status(self, status: Dict):
        """Update network status"""
        self.state['network_status'].update(status)
        self.save_state()
        
    def update_container_status(self, container: str, status: Dict):
        """Update container status"""
        self.state['containers'][container] = status
        self.save_state()
        
    def set_provisioning_complete(self):
        """Mark device provisioning as complete"""
        self.state['provisioning'] = {
            'completed': True,
            'timestamp': datetime.utcnow().isoformat()
        }
        self.save_state() 