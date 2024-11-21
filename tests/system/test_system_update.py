import unittest
import subprocess
import time

class TestSystemUpdate(unittest.TestCase):
    def setUp(self):
        # Prepare test environment
        subprocess.run(['prepare-test-environment.sh'])
        
    def test_system_update(self):
        # Get current version
        initial_version = self.get_system_version()
        
        # Trigger update
        subprocess.run(['stratura-update', '--version', 'test-version'])
        
        # Wait for update and reboot
        time.sleep(300)
        
        # Verify update
        new_version = self.get_system_version()
        self.assertNotEqual(initial_version, new_version)
        
        # Verify system state
        self.verify_system_state()
        
    def verify_system_state(self):
        # Check critical services
        services = ['stratura-supervisor', 'docker', 'networkmanager']
        for service in services:
            result = subprocess.run(['systemctl', 'is-active', service],
                                 capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), 'active') 