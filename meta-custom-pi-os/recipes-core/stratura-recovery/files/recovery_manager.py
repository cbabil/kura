#!/usr/bin/env python3

import os
import json
import logging
import subprocess
from datetime import datetime
from typing import Dict, Optional

class RecoveryManager:
    def __init__(self):
        self.config_path = '/etc/stratura/recovery-config.json'
        self.state_path = '/var/lib/stratura/recovery-state.json'
        self.load_config()
        
    def load_config(self):
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
            
    def create_recovery_point(self) -> str:
        """Create a recovery point for the system"""
        try:
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            recovery_path = f"/var/lib/stratura/recovery/{timestamp}"
            os.makedirs(recovery_path, exist_ok=True)
            
            # Backup critical configurations
            self.backup_configs(recovery_path)
            
            # Backup container data
            self.backup_container_data(recovery_path)
            
            # Save system state
            self.save_system_state(recovery_path)
            
            # Create recovery metadata
            self.create_recovery_metadata(recovery_path, timestamp)
            
            return recovery_path
            
        except Exception as e:
            logging.error(f"Recovery point creation failed: {e}")
            raise

    def backup_configs(self, recovery_path: str):
        """Backup critical system configurations"""
        config_backup_path = os.path.join(recovery_path, 'configs')
        os.makedirs(config_backup_path, exist_ok=True)
        
        # Backup network configs
        subprocess.run([
            'cp', '-r',
            '/etc/NetworkManager/system-connections',
            f"{config_backup_path}/network-connections"
        ])
        
        # Backup container configs
        subprocess.run([
            'cp', '-r',
            '/etc/stratura-supervisor',
            f"{config_backup_path}/supervisor"
        ])
        
        # Backup system configs
        subprocess.run([
            'tar', 'czf',
            f"{config_backup_path}/system-configs.tar.gz",
            '/etc/stratura'
        ])

    def backup_container_data(self, recovery_path: str):
        """Backup container data"""
        container_backup_path = os.path.join(recovery_path, 'containers')
        os.makedirs(container_backup_path, exist_ok=True)
        
        # Get list of containers
        result = subprocess.run(
            ['docker', 'ps', '-a', '--format', '{{.Names}}'],
            capture_output=True, text=True
        )
        
        for container in result.stdout.splitlines():
            # Backup container volume data
            volume_path = f"/var/lib/stratura/volumes/{container}"
            if os.path.exists(volume_path):
                subprocess.run([
                    'tar', 'czf',
                    f"{container_backup_path}/{container}-data.tar.gz",
                    volume_path
                ])

    def restore_system(self, recovery_point: str) -> bool:
        """Restore system from recovery point"""
        try:
            # Verify recovery point
            if not self.verify_recovery_point(recovery_point):
                raise Exception("Invalid recovery point")
                
            # Stop services
            self.stop_services()
            
            # Restore configurations
            self.restore_configs(recovery_point)
            
            # Restore container data
            self.restore_container_data(recovery_point)
            
            # Restore system state
            self.restore_system_state(recovery_point)
            
            # Restart services
            self.start_services()
            
            return True
            
        except Exception as e:
            logging.error(f"System restoration failed: {e}")
            return False

    def verify_recovery_point(self, recovery_point: str) -> bool:
        """Verify recovery point integrity"""
        try:
            # Check metadata
            metadata_path = os.path.join(recovery_point, 'metadata.json')
            if not os.path.exists(metadata_path):
                return False
                
            # Verify checksums
            checksums_path = os.path.join(recovery_point, 'checksums.json')
            if not os.path.exists(checksums_path):
                return False
                
            with open(checksums_path, 'r') as f:
                checksums = json.load(f)
                
            # Verify each backup file
            for file_path, expected_hash in checksums.items():
                full_path = os.path.join(recovery_point, file_path)
                if not os.path.exists(full_path):
                    return False
                    
                actual_hash = self.calculate_file_hash(full_path)
                if actual_hash != expected_hash:
                    return False
                    
            return True
            
        except Exception as e:
            logging.error(f"Recovery point verification failed: {e}")
            return False 