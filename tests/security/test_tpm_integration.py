import unittest
import subprocess
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

class TestTPMIntegration(unittest.TestCase):
    def setUp(self):
        self.tpm_status = subprocess.run(['tpm2_getcap', 'properties-fixed'],
                                       capture_output=True, text=True)
        
    def test_tpm_available(self):
        """Test TPM is available and accessible"""
        self.assertEqual(self.tpm_status.returncode, 0)
        
    def test_tpm_ownership(self):
        """Test TPM ownership is properly set"""
        result = subprocess.run(['tpm2_getcap', 'properties-owner'],
                              capture_output=True, text=True)
        self.assertIn('ownerAuthSet', result.stdout)
        
    def test_key_creation(self):
        """Test ability to create and use TPM-backed keys"""
        # Create primary key
        result = subprocess.run(['tpm2_createprimary', '-c', 'primary.ctx'],
                              capture_output=True)
        self.assertEqual(result.returncode, 0)
        
        # Create and load a key
        result = subprocess.run(['tpm2_create', '-C', 'primary.ctx',
                               '-u', 'key.pub', '-r', 'key.priv'],
                              capture_output=True)
        self.assertEqual(result.returncode, 0)
        
    def test_pcr_values(self):
        """Test PCR values are properly set"""
        result = subprocess.run(['tpm2_pcrread', 'sha256:0,1,2,3,4,5,6,7'],
                              capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertNotEqual(result.stdout.strip(), '') 