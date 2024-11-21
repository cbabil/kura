import unittest
import docker
from stratura.containers import ContainerManager

class TestContainerDeployment(unittest.TestCase):
    def setUp(self):
        self.container_manager = ContainerManager()
        self.client = docker.from_env()
        
    def tearDown(self):
        # Cleanup test containers
        containers = self.client.containers.list(
            filters={'label': 'test.stratura=true'}
        )
        for container in containers:
            container.remove(force=True)
            
    def test_container_deployment(self):
        # Test configuration
        config = {
            'name': 'test-container',
            'image': 'nginx:latest',
            'labels': {'test.stratura': 'true'}
        }
        
        # Deploy container
        container = self.container_manager.create_container(config)
        
        # Verify deployment
        self.assertIsNotNone(container)
        self.assertEqual(container.status, 'running')
        
        # Verify security settings
        container_info = container.attrs
        self.assertTrue(container_info['HostConfig']['ReadonlyRootfs'])
        self.assertIn('no-new-privileges', container_info['HostConfig']['SecurityOpt']) 