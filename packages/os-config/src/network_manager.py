#!/usr/bin/env python3

import dbus
import json
import logging
import subprocess
import datetime
from typing import Dict, List

class NetworkManager:
    def __init__(self):
        self.bus = dbus.SystemBus()
        self.nm = dbus.Interface(
            self.bus.get_object('org.freedesktop.NetworkManager', 
                              '/org/freedesktop/NetworkManager'),
            'org.freedesktop.NetworkManager'
        )

    def setup_network(self, config: Dict):
        if config.get('ethernet', {}).get('enable', True):
            self.setup_ethernet(config['ethernet'])
        
        if config.get('wifi', {}).get('enable', True):
            self.setup_wifi(config['wifi'])
            
        if config.get('cellular', {}).get('enable', False):
            self.setup_cellular(config['cellular'])

    def setup_wifi(self, config: Dict):
        for network in config.get('networks', []):
            connection = {
                '802-11-wireless': {
                    'ssid': network['ssid'],
                    'mode': 'infrastructure',
                    'security': '802-11-wireless-security'
                },
                '802-11-wireless-security': {
                    'key-mgmt': 'wpa-psk',
                    'psk': network['psk']
                },
                'ipv4': {'method': 'auto'},
                'ipv6': {'method': 'auto'}
            }
            self.add_connection(connection)

    def monitor_connectivity(self):
        def connectivity_changed(new_state):
            if new_state == 0:  # No connectivity
                self.handle_connection_loss()
            
        self.nm.connect_to_signal('StateChanged', connectivity_changed)

    def handle_connection_loss(self):
        """Handle network connection loss with failover"""
        logging.warning("Connection lost, initiating failover sequence")
        
        try:
            # Check current connection state
            active_conn = self.get_active_connection()
            if not active_conn:
                # Try primary connection first
                if self.try_primary_connection():
                    return
                    
                # Try WiFi connections
                if self.try_wifi_connections():
                    return
                    
                # Try cellular failover
                if self.try_cellular_failover():
                    return
                    
                # All connection attempts failed
                self.notify_connection_failure()
        except Exception as e:
            logging.error(f"Connection recovery failed: {e}")
            self.notify_connection_failure()

    def try_primary_connection(self):
        """Attempt to connect to primary network"""
        try:
            # Get primary connection
            primary = self.get_primary_connection()
            if not primary:
                return False
            
            # Activate connection
            self.nm.ActivateConnection(
                primary,
                self.get_primary_device(),
                '/'
            )
            
            # Wait for connection
            return self.wait_for_connection(timeout=30)
        except Exception as e:
            logging.error(f"Primary connection failed: {e}")
            return False

    def notify_connection_failure(self):
        """Notify system of connection failure"""
        try:
            # Log failure
            logging.error("All connection attempts failed")
            
            # Update system state
            with open('/var/lib/__BRAND__/network-state', 'w') as f:
                json.dump({
                    'status': 'disconnected',
                    'last_failure': datetime.datetime.now().isoformat(),
                    'recovery_attempts': self.recovery_attempts
                }, f)
            
            # Notify supervisor
            subprocess.run([
                'systemctl', 'notify',
                '--status="Network connection lost"',
                '--errno=1'
            ])
        except Exception as e:
            logging.error(f"Failed to notify connection failure: {e}")

    def setup_ethernet(self, config: Dict):
        """Setup ethernet connection"""
        connection = {
            '802-3-ethernet': {},
            'ipv4': {
                'method': config.get('ipv4_method', 'auto'),
                'addresses': config.get('static_ip', []),
                'dns': config.get('dns_servers', [])
            },
            'connection': {
                'id': f"ethernet-{config.get('interface', 'eth0')}",
                'type': '802-3-ethernet',
                'interface-name': config.get('interface', 'eth0')
            }
        }
        self.add_connection(connection)

    def add_connection(self, connection: Dict):
        """Add a new connection to NetworkManager"""
        settings = dbus.Dictionary(connection)
        self.nm.AddConnection(settings)

    def setup_cellular(self, config: Dict):
        """Setup cellular connection for failover"""
        if not config.get('apn'):
            return
        
        connection = {
            'gsm': {
                'apn': config['apn'],
                'number': config.get('number', '*99#'),
                'pin': config.get('pin', '')
            },
            'connection': {
                'id': f"cellular-{config.get('interface', 'wwan0')}",
                'type': 'gsm',
                'interface-name': config.get('interface', 'wwan0')
            }
        }
        self.add_connection(connection)