#!/usr/bin/env python3

import os
import json
import logging
import subprocess
from typing import Dict, List
import psutil

class PerformanceOptimizer:
    def __init__(self):
        self.config_path = '/etc/stratura/performance/config.json'
        self.load_config()
        
    def load_config(self):
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
            
    def optimize_system(self):
        """Apply system performance optimizations"""
        try:
            self.optimize_cpu()
            self.optimize_memory()
            self.optimize_io()
            self.optimize_network()
            self.optimize_containers()
            
        except Exception as e:
            logging.error(f"Performance optimization failed: {e}")
            raise

    def optimize_cpu(self):
        """Optimize CPU performance"""
        # Set CPU governor
        governor = self.config['cpu'].get('governor', 'ondemand')
        for cpu in range(psutil.cpu_count()):
            with open(f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_governor', 'w') as f:
                f.write(governor)
                
        # Configure CPU frequency scaling
        if 'freq_min' in self.config['cpu']:
            subprocess.run(['cpupower', 'frequency-set', 
                          '--min', str(self.config['cpu']['freq_min'])])
            
        if 'freq_max' in self.config['cpu']:
            subprocess.run(['cpupower', 'frequency-set',
                          '--max', str(self.config['cpu']['freq_max'])])

    def optimize_memory(self):
        """Optimize memory management"""
        sysctl_params = {
            'vm.swappiness': self.config['memory'].get('swappiness', 60),
            'vm.vfs_cache_pressure': self.config['memory'].get('cache_pressure', 100),
            'vm.dirty_ratio': self.config['memory'].get('dirty_ratio', 20),
            'vm.dirty_background_ratio': self.config['memory'].get('dirty_background_ratio', 10)
        }
        
        for param, value in sysctl_params.items():
            subprocess.run(['sysctl', '-w', f"{param}={value}"])
            
        # Configure transparent hugepages
        thp_enabled = self.config['memory'].get('transparent_hugepages', 'never')
        with open('/sys/kernel/mm/transparent_hugepage/enabled', 'w') as f:
            f.write(thp_enabled)

    def optimize_io(self):
        """Optimize I/O performance"""
        # Set I/O scheduler
        scheduler = self.config['io'].get('scheduler', 'deadline')
        for device in os.listdir('/sys/block'):
            if device.startswith(('sd', 'hd', 'mmcblk')):
                scheduler_path = f'/sys/block/{device}/queue/scheduler'
                if os.path.exists(scheduler_path):
                    with open(scheduler_path, 'w') as f:
                        f.write(scheduler)
                        
        # Configure I/O priorities
        ionice_settings = self.config['io'].get('ionice', {})
        for process, settings in ionice_settings.items():
            subprocess.run(['ionice', '-c', str(settings['class']),
                          '-n', str(settings['priority']), '-p', process])

    def optimize_network(self):
        """Optimize network performance"""
        sysctl_params = {
            'net.core.rmem_max': self.config['network'].get('rmem_max', 16777216),
            'net.core.wmem_max': self.config['network'].get('wmem_max', 16777216),
            'net.ipv4.tcp_rmem': self.config['network'].get('tcp_rmem', '4096 87380 16777216'),
            'net.ipv4.tcp_wmem': self.config['network'].get('tcp_wmem', '4096 65536 16777216'),
            'net.ipv4.tcp_congestion_control': self.config['network'].get('congestion_control', 'cubic')
        }
        
        for param, value in sysctl_params.items():
            subprocess.run(['sysctl', '-w', f"{param}={value}"])

    def optimize_containers(self):
        """Optimize container performance"""
        docker_config = {
            'storage-driver': self.config['containers'].get('storage_driver', 'overlay2'),
            'storage-opts': self.config['containers'].get('storage_opts', []),
            'default-ulimits': {
                'nofile': {'Soft': 65536, 'Hard': 65536}
            },
            'default-shm-size': self.config['containers'].get('shm_size', '64M'),
            'default-runtime': self.config['containers'].get('runtime', 'runc')
        }
        
        config_path = '/etc/docker/daemon.json'
        with open(config_path, 'w') as f:
            json.dump(docker_config, f, indent=4)
            
        subprocess.run(['systemctl', 'restart', 'docker'])

    def monitor_performance(self):
        """Monitor system performance metrics"""
        metrics = {
            'cpu_percent': psutil.cpu_percent(interval=1),
            'memory_percent': psutil.virtual_memory().percent,
            'disk_io': psutil.disk_io_counters(),
            'network_io': psutil.net_io_counters()
        }
        
        # Store metrics
        metrics_path = '/var/lib/stratura/performance/metrics.json'
        os.makedirs(os.path.dirname(metrics_path), exist_ok=True)
        
        with open(metrics_path, 'a') as f:
            json.dump(metrics, f)
            f.write('\n') 