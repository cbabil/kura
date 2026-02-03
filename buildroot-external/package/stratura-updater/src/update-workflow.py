#!/usr/bin/env python3

import json
import os
import subprocess
import logging
from enum import Enum
import datetime

class UpdateState(Enum):
    IDLE = "idle"
    DOWNLOADING = "downloading"
    VERIFYING = "verifying"
    INSTALLING = "installing"
    REBOOTING = "rebooting"
    FAILED = "failed"

class UpdateWorkflow:
    def __init__(self):
        self.state_file = '/var/lib/straturaOS/update-state.json'
        self.current_state = UpdateState.IDLE
        
    def save_state(self):
        with open(self.state_file, 'w') as f:
            json.dump({
                'state': self.current_state.value,
                'last_update': self.last_update,
                'current_version': self.current_version
            }, f)

    def verify_update(self, update_file):
        # Verify signature
        result = subprocess.run(['rauc', 'verify', update_file], 
                              capture_output=True, text=True)
        if result.returncode != 0:
            raise Exception("Update verification failed")
            
        # Check available space
        required_space = os.path.getsize(update_file)
        available_space = self.get_available_space()
        if available_space < required_space * 1.5:
            raise Exception("Insufficient space for update")

    def pre_update_hooks(self):
        # Stop non-essential services
        subprocess.run(['systemctl', 'stop', 'stratura-apps.target'])
        
        # Backup critical data
        subprocess.run(['stratura-backup', '--critical-only'])

    def post_update_hooks(self):
        # Update bootloader configuration
        subprocess.run(['update-bootloader-config'])
        
        # Mark update as successful
        with open('/var/lib/straturaOS/update-success', 'w') as f:
            f.write('1')

    def rollback_hooks(self):
        # Restore previous bootloader configuration
        subprocess.run(['restore-bootloader-config'])
        
        # Restore critical data
        subprocess.run(['stratura-restore', '--critical-only']) 

    def get_available_space(self):
        """Get available space in the target partition"""
        stat = os.statvfs('/var/lib/straturaOS')
        return stat.f_frsize * stat.f_bavail

    def trigger_update(self, version: str):
        try:
            self.current_state = UpdateState.DOWNLOADING
            self.save_state()
            
            update_file = self.download_update(version)
            if not update_file:
                raise Exception("Update download failed")
            
            self.current_state = UpdateState.VERIFYING
            self.save_state()
            self.verify_update(update_file)
            
            self.current_state = UpdateState.INSTALLING
            self.save_state()
            self.pre_update_hooks()
            
            if not self.install_update(update_file):
                self.rollback_hooks()
                raise Exception("Update installation failed")
            
            self.post_update_hooks()
            self.current_state = UpdateState.REBOOTING
            self.save_state()
            
            subprocess.run(['systemctl', 'reboot'])
            
        except Exception as e:
            self.current_state = UpdateState.FAILED
            self.save_state()
            raise e

    def install_update(self, update_file: str) -> bool:
        """Install update with rollback protection"""
        try:
            # Create recovery point
            self.create_recovery_point()
            
            # Verify update file integrity
            if not self.verify_update_integrity(update_file):
                raise Exception("Update integrity check failed")
            
            # Check system requirements
            self.check_system_requirements()
            
            # Install update
            result = subprocess.run(
                ['rauc', 'install', update_file],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                raise Exception(f"Update installation failed: {result.stderr}")
            
            # Verify installation
            if not self.verify_installation():
                raise Exception("Installation verification failed")
            
            return True
            
        except Exception as e:
            logging.error(f"Update installation failed: {e}")
            self.trigger_rollback()
            return False

    def verify_installation(self) -> bool:
        """Verify successful installation"""
        try:
            # Check RAUC status
            result = subprocess.run(
                ['rauc', 'status', '--detailed'],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False
            
            # Verify bootloader configuration
            if not self.verify_bootloader_config():
                return False
            
            # Verify system integrity
            if not self.verify_system_integrity():
                return False
            
            return True
            
        except Exception as e:
            logging.error(f"Installation verification failed: {e}")
            return False

    def create_recovery_point(self):
        """Create system recovery point"""
        try:
            # Backup bootloader configuration
            subprocess.run(['cp', '/boot/config.txt', '/boot/config.txt.bak'])
            
            # Backup critical data
            backup_path = f"/var/lib/straturaOS/backups/{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
            os.makedirs(backup_path, exist_ok=True)
            
            subprocess.run([
                'tar', 'czf',
                f"{backup_path}/critical_data.tar.gz",
                '/var/lib/straturaOS/data'
            ])
            
            # Save current state
            with open(f"{backup_path}/state.json", 'w') as f:
                json.dump({
                    'version': self.current_version,
                    'timestamp': datetime.datetime.now().isoformat(),
                    'config': self.get_system_config()
                }, f)
            
        except Exception as e:
            logging.error(f"Failed to create recovery point: {e}")
            raise