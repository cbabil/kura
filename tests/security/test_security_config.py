import unittest
import json
import os

class TestSecurityConfiguration(unittest.TestCase):
    def setUp(self):
        with open('/etc/stratura/security/config.json') as f:
            self.config = json.load(f)
            
    def test_secure_boot_enabled(self):
        """Test secure boot is enabled"""
        self.assertTrue(self.config['secure_boot']['enabled'])
        self.assertTrue(self.config['secure_boot']['verify_kernel'])
        
    def test_tpm_configuration(self):
        """Test TPM configuration"""
        self.assertTrue(self.config['tpm']['enabled'])
        self.assertEqual(self.config['tpm']['pcr_banks'], ['sha256'])
        
    def test_network_security(self):
        """Test network security configuration"""
        self.assertTrue(self.config['network_security']['firewall_enabled'])
        self.assertTrue(self.config['network_security']['fail2ban_enabled'])
        
    def test_update_security(self):
        """Test update security configuration"""
        self.assertTrue(self.config['update_security']['verify_signatures'])
        self.assertTrue(self.config['update_security']['rollback_protection']) 