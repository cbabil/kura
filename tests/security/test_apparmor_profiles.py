import unittest
import subprocess
import os

class TestAppArmorProfiles(unittest.TestCase):
    def setUp(self):
        self.aa_status = subprocess.run(['aa-status'], 
                                      capture_output=True, 
                                      text=True).stdout
        
    def test_apparmor_enabled(self):
        """Test AppArmor is enabled"""
        self.assertIn('apparmor module is loaded', self.aa_status)
        
    def test_supervisor_profile_loaded(self):
        """Test Supervisor AppArmor profile is loaded"""
        self.assertIn('stratura-supervisor', self.aa_status)
        
    def test_supervisor_profile_enforced(self):
        """Test Supervisor profile is enforced"""
        result = subprocess.run(['aa-status', '--enforced'],
                              capture_output=True, text=True)
        self.assertIn('stratura-supervisor', result.stdout)
        
    def test_profile_violations(self):
        """Test for AppArmor profile violations"""
        result = subprocess.run(['dmesg', '|', 'grep', 'apparmor="DENIED"'],
                              capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), '') 