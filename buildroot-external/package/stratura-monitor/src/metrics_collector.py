#!/usr/bin/env python3

import psutil
import json
import time
import logging
import os
from datetime import datetime
from typing import Dict, List
import requests
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
from stratura.containers import ContainerManager

class MetricsCollector:
    def __init__(self):
        self.config_path = '/etc/stratura/metrics-config.json'
        self.load_config()
        self.setup_prometheus()
        
    def load_config(self):
        with open(self.config_path) as f:
            self.config = json.load(f)
            
    def setup_prometheus(self):
        """Setup Prometheus metrics"""
        self.registry = CollectorRegistry()
        
        # System metrics
        self.cpu_usage = Gauge('system_cpu_usage', 'CPU usage percentage',
                             registry=self.registry)
        self.memory_usage = Gauge('system_memory_usage', 'Memory usage percentage',
                                registry=self.registry)
        self.disk_usage = Gauge('system_disk_usage', 'Disk usage percentage',
                              registry=self.registry)
        self.network_rx = Gauge('system_network_rx_bytes', 'Network bytes received',
                              registry=self.registry)
        self.network_tx = Gauge('system_network_tx_bytes', 'Network bytes sent',
                              registry=self.registry)
                              
        # Container metrics
        self.container_cpu = Gauge('container_cpu_usage', 'Container CPU usage',
                                 ['name'], registry=self.registry)
        self.container_memory = Gauge('container_memory_usage', 'Container memory usage',
                                    ['name'], registry=self.registry)
                                    
    def collect_metrics(self):
        """Collect system metrics"""
        try:
            # System metrics
            self.cpu_usage.set(psutil.cpu_percent())
            self.memory_usage.set(psutil.virtual_memory().percent)
            self.disk_usage.set(psutil.disk_usage('/').percent)
            
            net = psutil.net_io_counters()
            self.network_rx.set(net.bytes_recv)
            self.network_tx.set(net.bytes_sent)
            
            # Container metrics
            self.collect_container_metrics()
            
            # Push to Prometheus
            if self.config.get('prometheus_gateway'):
                push_to_gateway(
                    self.config['prometheus_gateway'],
                    job='stratura_device',
                    registry=self.registry
                )
                
            # Store locally
            self.store_metrics()
            
        except Exception as e:
            logging.error(f"Failed to collect metrics: {e}")
            
    def collect_container_metrics(self):
        """Collect container metrics"""
        try:
            container_manager = ContainerManager()
            for container in container_manager.list_containers():
                stats = container.stats(stream=False)
                
                # CPU usage
                cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - \
                           stats['precpu_stats']['cpu_usage']['total_usage']
                system_delta = stats['cpu_stats']['system_cpu_usage'] - \
                             stats['precpu_stats']['system_cpu_usage']
                cpu_percent = (cpu_delta / system_delta) * 100
                self.container_cpu.labels(container.name).set(cpu_percent)
                
                # Memory usage
                memory_usage = stats['memory_stats']['usage']
                memory_limit = stats['memory_stats']['limit']
                memory_percent = (memory_usage / memory_limit) * 100
                self.container_memory.labels(container.name).set(memory_percent)
                
        except Exception as e:
            logging.error(f"Failed to collect container metrics: {e}")
            
    def store_metrics(self):
        """Store metrics locally"""
        metrics_file = '/var/lib/stratura/metrics.json'
        
        metrics = {
            'timestamp': datetime.utcnow().isoformat(),
            'system': {
                'cpu': psutil.cpu_percent(),
                'memory': psutil.virtual_memory().percent,
                'disk': psutil.disk_usage('/').percent,
                'network': dict(psutil.net_io_counters()._asdict())
            },
            'containers': {}
        }
        
        # Add container metrics
        container_manager = ContainerManager()
        for container in container_manager.list_containers():
            metrics['containers'][container.name] = container.stats(stream=False)
            
        # Rotate metrics file if too large
        if os.path.exists(metrics_file) and \
           os.path.getsize(metrics_file) > self.config['max_metrics_size']:
            os.rename(metrics_file, f"{metrics_file}.{int(time.time())}")
            
        # Write metrics
        with open(metrics_file, 'a') as f:
            json.dump(metrics, f)
            f.write('\n')
            
    def run(self):
        """Run metrics collection"""
        while True:
            try:
                self.collect_metrics()
                time.sleep(self.config['collection_interval'])
            except Exception as e:
                logging.error(f"Metrics collection failed: {e}")
                time.sleep(60)

if __name__ == "__main__":
    collector = MetricsCollector()
    collector.run() 