import unittest
import time
import psutil
import docker

class TestSystemPerformance(unittest.TestCase):
    def setUp(self):
        self.client = docker.from_env()
        
    def test_container_startup_time(self):
        start_time = time.time()
        
        container = self.client.containers.run(
            'nginx:latest',
            detach=True,
            labels={'test.stratura': 'true'}
        )
        
        # Wait for container to be healthy
        while container.status != 'running':
            container.reload()
            if time.time() - start_time > 10:
                self.fail("Container startup timeout")
                
        startup_time = time.time() - start_time
        self.assertLess(startup_time, 5)  # Should start in under 5 seconds
        
    def test_system_resource_usage(self):
        # Monitor CPU usage
        cpu_usage = psutil.cpu_percent(interval=1)
        self.assertLess(cpu_usage, 80)  # CPU usage should be under 80%
        
        # Monitor memory usage
        memory = psutil.virtual_memory()
        self.assertLess(memory.percent, 85)  # Memory usage should be under 85% 