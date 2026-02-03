#!/usr/bin/env python3

import psutil
import json
import logging
import time
import requests
from datetime import datetime
from typing import Dict, List
from prometheus_client import start_http_server, Gauge, Counter

class SystemMonitor:
    def __init__(self, config_path: str = '/etc/stratura/monitor-config.json'):
        self.load_config(config_path)
        self.setup_metrics()
        self.alert_history = []
        
    def setup_metrics(self):
        # System metrics
        self.cpu_usage = Gauge('system_cpu_usage', 'CPU usage percentage')
        self.memory_usage = Gauge('system_memory_usage', 'Memory usage percentage')
        self.disk_usage = Gauge('system_disk_usage', 'Disk usage percentage')
        self.network_errors = Counter('system_network_errors', 'Network error count')
        
        # Container metrics
        self.container_status = Gauge('container_status', 'Container status', ['name'])
        self.container_restarts = Counter('container_restarts', 'Container restart count', ['name'])
        
        # Update metrics
        self.update_status = Gauge('update_status', 'Update status')
        self.failed_updates = Counter('failed_updates', 'Failed update count')

    def monitor_system(self):
        while True:
            try:
                # Collect system metrics
                self.collect_system_metrics()
                
                # Check thresholds and alert if necessary
                self.check_thresholds()
                
                # Store metrics history
                self.store_metrics()
                
                time.sleep(self.config['polling_interval'])
                
            except Exception as e:
                logging.error(f"Monitoring error: {e}")
                self.alert_critical_failure("Monitoring system failure", str(e))
                time.sleep(60)

    def collect_system_metrics(self):
        # CPU metrics
        self.cpu_usage.set(psutil.cpu_percent())
        
        # Memory metrics
        mem = psutil.virtual_memory()
        self.memory_usage.set(mem.percent)
        
        # Disk metrics
        disk = psutil.disk_usage('/')
        self.disk_usage.set(disk.percent)
        
        # Network metrics
        net_counters = psutil.net_io_counters()
        if net_counters.errin > 0 or net_counters.errout > 0:
            self.network_errors.inc()

    def check_thresholds(self):
        alerts = []
        
        # Check CPU threshold
        if psutil.cpu_percent() > self.config['thresholds']['cpu_critical']:
            alerts.append(("CPU Usage Critical", "CPU usage exceeded critical threshold"))
            
        # Check memory threshold
        if psutil.virtual_memory().percent > self.config['thresholds']['memory_critical']:
            alerts.append(("Memory Usage Critical", "Memory usage exceeded critical threshold"))
            
        # Check disk threshold
        if psutil.disk_usage('/').percent > self.config['thresholds']['disk_critical']:
            alerts.append(("Disk Usage Critical", "Disk usage exceeded critical threshold"))
            
        # Send alerts if any
        for alert in alerts:
            self.send_alert(*alert)

    def send_alert(self, title: str, message: str, level: str = "critical"):
        try:
            alert_data = {
                "title": title,
                "message": message,
                "level": level,
                "timestamp": datetime.utcnow().isoformat(),
                "device_id": self.config['device_id']
            }
            
            # Send to monitoring service
            response = requests.post(
                f"{self.config['alert_endpoint']}/alerts",
                json=alert_data,
                headers={"Authorization": f"Bearer {self.config['api_key']}"}
            )
            
            if response.status_code != 200:
                logging.error(f"Failed to send alert: {response.text}")
                
            # Store alert history
            self.alert_history.append(alert_data)
            
            # Trim alert history if too long
            if len(self.alert_history) > 1000:
                self.alert_history = self.alert_history[-1000:]
                
        except Exception as e:
            logging.error(f"Alert sending failed: {e}")

    def store_metrics(self):
        metrics_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "cpu_usage": psutil.cpu_percent(),
            "memory_usage": psutil.virtual_memory().percent,
            "disk_usage": psutil.disk_usage('/').percent,
            "network_stats": dict(psutil.net_io_counters()._asdict())
        }
        
        # Store locally
        with open('/var/lib/stratura/metrics.json', 'a') as f:
            json.dump(metrics_data, f)
            f.write('\n') 