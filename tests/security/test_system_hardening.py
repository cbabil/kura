import unittest
import subprocess
import socket

class TestSystemHardening(unittest.TestCase):
    def test_secure_boot(self):
        result = subprocess.run(['stratura-verify-boot'],
                              capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        
    def test_selinux_enforcement(self):
        result = subprocess.run(['getenforce'],
                              capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), 'Enforcing')
        
    def test_firewall_rules(self):
        # Test closed ports
        closed_ports = [21, 23, 25, 80]
        for port in closed_ports:
            with self.assertRaises(ConnectionRefusedError):
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(1)
                    s.connect(('localhost', port))
                    
        # Test open ports
        open_ports = [22, 48484]  # SSH and API
        for port in open_ports:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(1)
                s.connect(('localhost', port)) 