#!/usr/bin/env python3

import psutil
import json
import logging
import os
from typing import Dict, List
import subprocess
import yaml
from pathlib import Path
from datetime import datetime

class ResourceManager:
    def __init__(self):
        self.config_path = '/etc/stratura/optimization/system-tuning.yml'
        self.metrics_path = '/var/lib/stratura/metrics'
        self.load_config()
        self.setup_logging()
        
    def setup_logging(self):
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/stratura/resource-manager.log'),
                logging.StreamHandler()
            ]
        )
        
    def load_config(self):
        """Load configuration with validation"""
        try:
            with open(self.config_path) as f:
                self.config = yaml.safe_load(f)
            self.validate_config()
        except Exception as e:
            logging.error(f"Failed to load configuration: {e}")
            raise
            
    def validate_config(self):
        """Validate configuration values"""
        required_sections = ['system', 'containers', 'resources']
        for section in required_sections:
            if section not in self.config:
                raise ValueError(f"Missing required section: {section}")
                
    def apply_system_optimizations(self):
        """Apply system-wide optimizations with validation"""
        try:
            # Create metrics directory
            Path(self.metrics_path).mkdir(parents=True, exist_ok=True)
            
            # Apply optimizations
            self.optimize_cpu()
            self.optimize_memory()
            self.optimize_io()
            self.optimize_network()
            self.optimize_containers()
            
            # Verify optimizations
            self.verify_optimizations()
            
            return True
        except Exception as e:
            logging.error(f"Failed to apply optimizations: {e}")
            return False
            
    def optimize_cpu(self):
        """Apply CPU optimizations with error handling"""
        cpu_config = self.config['system']['cpu']
        
        try:
            # Set CPU governor
            for cpu in range(psutil.cpu_count()):
                governor_path = f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_governor'
                if os.path.exists(governor_path):
                    with open(governor_path, 'w') as f:
                        f.write(cpu_config['governor'])
                        
            # Set frequency limits
            subprocess.run(['cpupower', 'frequency-set',
                          '--min', str(cpu_config['min_freq']),
                          '--max', str(cpu_config['max_freq'])],
                         check=True)
                         
            # Configure CPU boost
            boost_path = '/sys/devices/system/cpu/cpufreq/boost'
            if os.path.exists(boost_path):
                with open(boost_path, 'w') as f:
                    f.write('1' if cpu_config['boost'] else '0')
                    
        except Exception as e:
            logging.error(f"CPU optimization failed: {e}")
            raise
            
    def optimize_memory(self):
        """Apply memory optimizations"""
        mem_config = self.config['system']['memory']
        
        # Set memory parameters
        sysctl_params = {
            'vm.swappiness': mem_config['swappiness'],
            'vm.vfs_cache_pressure': mem_config['vfs_cache_pressure'],
            'vm.dirty_ratio': mem_config['dirty_ratio'],
            'vm.dirty_background_ratio': mem_config['dirty_background_ratio']
        }
        
        for param, value in sysctl_params.items():
            subprocess.run(['sysctl', '-w', f"{param}={value}"])
            
    def optimize_io(self):
        """Apply I/O optimizations with validation"""
        io_config = self.config['system']['io']
        
        try:
            # Set I/O scheduler
            for device in self.get_block_devices():
                scheduler_path = f'/sys/block/{device}/queue/scheduler'
                if os.path.exists(scheduler_path):
                    with open(scheduler_path, 'w') as f:
                        f.write(io_config['scheduler'])
                        
            # Set read ahead
            for device in self.get_block_devices():
                ra_path = f'/sys/block/{device}/queue/read_ahead_kb'
                if os.path.exists(ra_path):
                    with open(ra_path, 'w') as f:
                        f.write(str(io_config['read_ahead_kb']))
                        
        except Exception as e:
            logging.error(f"I/O optimization failed: {e}")
            raise
            
    def optimize_network(self):
        """Apply network optimizations"""
        net_config = self.config['system']['network']
        
        sysctl_params = {
            'net.ipv4.tcp_congestion_control': net_config['tcp_congestion'],
            'net.ipv4.tcp_fastopen': net_config['tcp_fastopen'],
            'net.core.rmem_max': net_config['rmem_max'],
            'net.core.wmem_max': net_config['wmem_max']
        }
        
        for param, value in sysctl_params.items():
            subprocess.run(['sysctl', '-w', f"{param}={value}"])
            
    def optimize_containers(self):
        """Apply container optimizations"""
        container_config = self.config['containers']
        
        # Update Docker daemon configuration
        docker_config = {
            'default-shm-size': container_config['default_shm_size'],
            'storage-driver': container_config['storage_driver'],
            'max-concurrent-downloads': container_config['max_concurrent_downloads'],
            'max-concurrent-uploads': container_config['max_concurrent_uploads']
        }
        
        with open('/etc/docker/daemon.json', 'w') as f:
            json.dump(docker_config, f, indent=2)
            
        # Restart Docker daemon
        subprocess.run(['systemctl', 'restart', 'docker'])
        
    def get_block_devices(self) -> List[str]:
        """Get list of block devices with validation"""
        try:
            return [d for d in os.listdir('/sys/block') 
                    if d.startswith(('sd', 'hd', 'mmcblk', 'nvme'))]
        except Exception as e:
            logging.error(f"Failed to get block devices: {e}")
            raise
            
    def verify_optimizations(self):
        """Verify applied optimizations"""
        try:
            # Verify CPU settings
            self.verify_cpu_settings()
            
            # Verify memory settings
            self.verify_memory_settings()
            
            # Verify I/O settings
            self.verify_io_settings()
            
            # Store verification results
            self.store_verification_results()
            
        except Exception as e:
            logging.error(f"Optimization verification failed: {e}")
            raise
            
    def store_verification_results(self):
        """Store optimization verification results"""
        results = {
            'timestamp': datetime.utcnow().isoformat(),
            'cpu': self.get_cpu_settings(),
            'memory': self.get_memory_settings(),
            'io': self.get_io_settings(),
            'network': self.get_network_settings()
        }
        
        results_path = os.path.join(self.metrics_path, 'optimization-results.json')
        with open(results_path, 'w') as f:
            json.dump(results, f, indent=2)
        
    def get_cpu_settings(self):
        """Get CPU settings"""
        cpu_config = self.config['system']['cpu']
        return {
            'governor': cpu_config['governor'],
            'min_freq': cpu_config['min_freq'],
            'max_freq': cpu_config['max_freq'],
            'boost': cpu_config['boost']
        }
        
    def get_memory_settings(self):
        """Get memory settings"""
        mem_config = self.config['system']['memory']
        return {
            'swappiness': mem_config['swappiness'],
            'vfs_cache_pressure': mem_config['vfs_cache_pressure'],
            'dirty_ratio': mem_config['dirty_ratio'],
            'dirty_background_ratio': mem_config['dirty_background_ratio']
        }
        
    def get_io_settings(self):
        """Get I/O settings"""
        io_config = self.config['system']['io']
        return {
            'scheduler': io_config['scheduler'],
            'read_ahead_kb': io_config['read_ahead_kb']
        }
        
    def get_network_settings(self):
        """Get network settings"""
        net_config = self.config['system']['network']
        return {
            'tcp_congestion': net_config['tcp_congestion'],
            'tcp_fastopen': net_config['tcp_fastopen'],
            'rmem_max': net_config['rmem_max'],
            'wmem_max': net_config['wmem_max']
        }
        
    def monitor_resources(self):
        """Monitor system resources"""
        metrics = {
            'cpu': psutil.cpu_percent(interval=1),
            'memory': psutil.virtual_memory().percent,
            'disk': psutil.disk_usage('/').percent,
            'network': self.get_network_stats()
        }
        
        self.check_thresholds(metrics)
        self.store_metrics(metrics)
        
    def check_thresholds(self, metrics: Dict):
        """Check resource thresholds"""
        thresholds = self.config['metrics']['thresholds']
        
        for resource, value in metrics.items():
            if resource in thresholds:
                if value >= thresholds[resource]['critical']:
                    self.handle_critical_threshold(resource, value)
                elif value >= thresholds[resource]['warning']:
                    self.handle_warning_threshold(resource, value)
                    
    def handle_critical_threshold(self, resource: str, value: float):
        """Handle critical threshold breach"""
        logging.critical(f"{resource} usage critical: {value}%")
        
        # Take corrective action
        if resource == 'memory':
            self.free_memory()
        elif resource == 'disk':
            self.cleanup_disk()
            
    def free_memory(self):
        """Free up system memory"""
        subprocess.run(['sync'])
        with open('/proc/sys/vm/drop_caches', 'w') as f:
            f.write('3')
            
    def cleanup_disk(self):
        """Clean up disk space"""
        # Clean Docker
        subprocess.run(['docker', 'system', 'prune', '-af'])
        
        # Clean logs
        subprocess.run(['journalctl', '--vacuum-time=2d']) 