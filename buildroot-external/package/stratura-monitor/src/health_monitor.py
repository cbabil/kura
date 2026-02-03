#!/usr/bin/env python3

import psutil
import json
import logging
import time
from typing import Dict, List
from datetime import datetime
import subprocess
import requests

class HealthMonitor:
    def __init__(self):
        self.config_path = '/etc/stratura/health-config.json'
        self.load_config()
        self.setup_monitoring()
        
    def load_config(self):
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
            
    def setup_monitoring(self):
        """Setup monitoring thresholds and checks"""
        self.checks = {
            'cpu': self.check_cpu,
            'memory': self.check_memory,
            'disk': self.check_disk,
            'network': self.check_network,
            'temperature': self.check_temperature,
            'containers': self.check_containers,
            'services': self.check_services
        }
        
    def run_health_check(self) -> Dict:
        """Run comprehensive health check"""
        try:
            results = {}
            for check_name, check_func in self.checks.items():
                try:
                    results[check_name] = check_func()
                except Exception as e:
                    logging.error(f"Health check failed for {check_name}: {e}")
                    results[check_name] = {
                        'status': 'error',
                        'error': str(e)
                    }
                    
            self.store_health_results(results)
            self.analyze_health_results(results)
            
            return results
            
        except Exception as e:
            logging.error(f"Health check failed: {e}")
            raise

    def check_cpu(self) -> Dict:
        """Check CPU health"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_freq = psutil.cpu_freq()
            cpu_count = psutil.cpu_count()
            
            # Check CPU temperature
            temp = self.get_cpu_temperature()
            
            status = 'healthy'
            warnings = []
            
            if cpu_percent > self.config['thresholds']['cpu_critical']:
                status = 'critical'
                warnings.append(f"CPU usage critical: {cpu_percent}%")
            elif cpu_percent > self.config['thresholds']['cpu_warning']:
                status = 'warning'
                warnings.append(f"CPU usage high: {cpu_percent}%")
                
            if temp > self.config['thresholds']['temp_critical']:
                status = 'critical'
                warnings.append(f"CPU temperature critical: {temp}°C")
                
            return {
                'status': status,
                'usage_percent': cpu_percent,
                'frequency': cpu_freq.current if cpu_freq else None,
                'temperature': temp,
                'warnings': warnings
            }
            
        except Exception as e:
            logging.error(f"CPU health check failed: {e}")
            raise

    def check_memory(self) -> Dict:
        """Check memory health"""
        try:
            memory = psutil.virtual_memory()
            swap = psutil.swap_memory()
            
            status = 'healthy'
            warnings = []
            
            if memory.percent > self.config['thresholds']['memory_critical']:
                status = 'critical'
                warnings.append(f"Memory usage critical: {memory.percent}%")
            elif memory.percent > self.config['thresholds']['memory_warning']:
                status = 'warning'
                warnings.append(f"Memory usage high: {memory.percent}%")
                
            if swap.percent > self.config['thresholds']['swap_critical']:
                status = 'critical'
                warnings.append(f"Swap usage critical: {swap.percent}%")
                
            return {
                'status': status,
                'memory_used_percent': memory.percent,
                'swap_used_percent': swap.percent,
                'warnings': warnings
            }
            
        except Exception as e:
            logging.error(f"Memory health check failed: {e}")
            raise

    def analyze_health_results(self, results: Dict):
        """Analyze health check results and take action if needed"""
        try:
            critical_issues = []
            warnings = []
            
            for component, result in results.items():
                if result['status'] == 'critical':
                    critical_issues.append(f"{component}: {result.get('warnings', [])}")
                elif result['status'] == 'warning':
                    warnings.append(f"{component}: {result.get('warnings', [])}")
                    
            if critical_issues:
                self.handle_critical_issues(critical_issues)
            if warnings:
                self.handle_warnings(warnings)
                
        except Exception as e:
            logging.error(f"Health analysis failed: {e}")
            raise

    def handle_critical_issues(self, issues: List[str]):
        """Handle critical health issues"""
        try:
            # Log critical issues
            for issue in issues:
                logging.critical(f"Critical health issue: {issue}")
                
            # Notify monitoring system
            self.send_alert('critical', issues)
            
            # Take corrective action
            self.take_corrective_action(issues)
            
        except Exception as e:
            logging.error(f"Failed to handle critical issues: {e}")
            raise

    def take_corrective_action(self, issues: List[str]):
        """Take corrective action based on health issues"""
        try:
            for issue in issues:
                if 'CPU usage critical' in issue:
                    self.handle_cpu_overload()
                elif 'Memory usage critical' in issue:
                    self.handle_memory_overload()
                elif 'Disk usage critical' in issue:
                    self.handle_disk_full()
                elif 'Container' in issue:
                    self.handle_container_issue(issue)
                    
        except Exception as e:
            logging.error(f"Corrective action failed: {e}")
            raise

    def send_alert(self, severity: str, issues: List[str]):
        """Send health alert to monitoring system"""
        try:
            alert_data = {
                'severity': severity,
                'issues': issues,
                'device_id': self.get_device_id(),
                'timestamp': datetime.utcnow().isoformat()
            }
            
            # Send to monitoring service
            response = requests.post(
                f"{self.config['alert_endpoint']}/alerts",
                json=alert_data,
                headers={"Authorization": f"Bearer {self.config['api_key']}"}
            )
            
            if response.status_code != 200:
                logging.error(f"Failed to send alert: {response.text}")
                
        except Exception as e:
            logging.error(f"Failed to send alert: {e}")
            raise 