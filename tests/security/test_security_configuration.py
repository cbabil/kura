import unittest
import subprocess
import socket
import ssl
import os

class TestSecurityConfiguration(unittest.TestCase):
    def test_tpm_configuration(self):
        """Test TPM configuration and key storage"""
        result = subprocess.run(['tpm2_getcap', 'properties-fixed'],
                              capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        
        # Verify TPM is enabled and accessible
        result = subprocess.run(['tpm2_pcrread'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)

    def test_ssl_configuration(self):
        """Test SSL/TLS configuration"""
        context = ssl.create_default_context()
        with socket.create_connection(('localhost', 48484)) as sock:
            with context.wrap_socket(sock, server_hostname='localhost') as ssock:
                self.assertGreaterEqual(ssock.version(), 'TLSv1.3')
                
    def test_selinux_policies(self):
        """Test SELinux policies"""
        result = subprocess.run(['sestatus'], capture_output=True, text=True)
        self.assertIn('enforcing', result.stdout.lower())
        
        # Check container policy
        result = subprocess.run(['semodule', '-l'], capture_output=True, text=True)
        self.assertIn('stratura_container', result.stdout)

    def test_apparmor_profiles(self):
        """Test AppArmor profiles"""
        result = subprocess.run(['aa-status'], capture_output=True, text=True)
        self.assertIn('stratura-supervisor', result.stdout)
        self.assertIn('stratura-container-default', result.stdout) 