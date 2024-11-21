import unittest
import subprocess
import os

class TestSELinuxPolicy(unittest.TestCase):
    def setUp(self):
        self.selinux_status = subprocess.run(['getenforce'], 
                                           capture_output=True, 
                                           text=True).stdout.strip()
        
    def test_selinux_enforcing(self):
        """Test SELinux is in enforcing mode"""
        self.assertEqual(self.selinux_status, 'Enforcing')
        
    def test_stratura_supervisor_context(self):
        """Test Supervisor process has correct SELinux context"""
        result = subprocess.run(['ps', '-eZ', '|', 'grep', 'stratura-supervisor'],
                              capture_output=True, text=True)
        self.assertIn('system_u:system_r:stratura_supervisor_t', result.stdout)
        
    def test_stratura_data_context(self):
        """Test data directory has correct SELinux context"""
        result = subprocess.run(['ls', '-Z', '/var/lib/stratura'],
                              capture_output=True, text=True)
        self.assertIn('system_u:object_r:stratura_data_t', result.stdout)
        
    def test_policy_violations(self):
        """Test for SELinux policy violations"""
        result = subprocess.run(['ausearch', '-m', 'AVC', '-ts', 'recent'],
                              capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), '') 