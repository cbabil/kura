import unittest
from unittest.mock import Mock, patch
from stratura.update import UpdateWorkflow

class TestUpdateWorkflow(unittest.TestCase):
    def setUp(self):
        self.workflow = UpdateWorkflow()
        
    @patch('subprocess.run')
    def test_verify_update(self, mock_run):
        # Setup
        mock_run.return_value.returncode = 0
        
        # Test
        self.workflow.verify_update('test.raucb')
        
        # Assert
        mock_run.assert_called_with(
            ['rauc', 'verify', 'test.raucb'],
            capture_output=True,
            text=True
        )
        
    @patch('os.statvfs')
    def test_insufficient_space(self, mock_statvfs):
        # Setup
        mock_statvfs.return_value.f_frsize = 4096
        mock_statvfs.return_value.f_bavail = 100
        
        # Test & Assert
        with self.assertRaises(Exception):
            self.workflow.verify_update('large_update.raucb') 