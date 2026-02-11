"""Shared fixtures for StraturaOS service tests."""

import json
import os
import sys

import pytest

# Add package source paths so tests can import modules
_PACKAGES_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "packages",
)

_SRC_DIRS = [
    os.path.join(_PACKAGES_ROOT, "stratura-supervisor", "src"),
    os.path.join(_PACKAGES_ROOT, "stratura-config", "src"),
    os.path.join(_PACKAGES_ROOT, "stratura-monitor", "src"),
    os.path.join(_PACKAGES_ROOT, "stratura-security", "src"),
]

for src_dir in _SRC_DIRS:
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)


@pytest.fixture()
def mock_config(tmp_path):
    """Create a temporary directory with a sample config.json."""
    config = {
        "device_id": "test-device-001",
        "api_key": "test-api-key",
        "alert_endpoint": "https://monitor.example.com",
        "polling_interval": 10,
        "collection_interval": 15,
        "max_metrics_size": 1048576,
        "prometheus_gateway": "http://localhost:9091",
        "thresholds": {
            "cpu_warning": 70,
            "cpu_critical": 90,
            "memory_warning": 75,
            "memory_critical": 95,
            "disk_warning": 80,
            "disk_critical": 95,
            "swap_critical": 80,
            "temp_critical": 85,
        },
        "network": {
            "ethernet": {"enable": True, "interface": "eth0"},
        },
        "containers": [
            {"name": "app1", "image": "registry.example.com/app1:latest"},
        ],
        "apparmor_profiles": [],
        "seccomp_profiles": [],
    }
    config_file = tmp_path / "config.json"
    config_file.write_text(json.dumps(config, indent=2))
    return tmp_path, config


@pytest.fixture()
def mock_rootfs(tmp_path):
    """Create a temporary rootfs-like directory structure."""
    dirs = [
        "etc/stratura/certs",
        "etc/stratura/keys",
        "etc/stratura/security/seccomp",
        "etc/stratura/selinux",
        "etc/ssh",
        "etc/audit/rules.d",
        "etc/apparmor.d/stratura",
        "var/lib/stratura/volumes",
        "var/lock",
        "var/log",
        "boot",
    ]
    for d in dirs:
        (tmp_path / d).mkdir(parents=True, exist_ok=True)
    return tmp_path


@pytest.fixture()
def containers_config():
    """Sample containers.json content."""
    return {
        "containers": [
            {
                "name": "test-app",
                "image": "registry.example.com/app:latest",
                "version": "1.0.0",
                "restart_policy": "always",
                "resources": {"memory": "512m", "cpu_shares": 512},
                "network": {
                    "mode": "bridge",
                    "ports": [
                        {"host": "8080", "container": "80", "protocol": "tcp"}
                    ],
                },
                "environment": {"APP_ENV": "production"},
                "volumes": ["/data/app:/app/data:ro"],
                "healthcheck": {
                    "cmd": "curl -f http://localhost/health",
                    "interval": "30s",
                    "timeout": "10s",
                    "retries": 3,
                },
            }
        ]
    }


@pytest.fixture()
def health_config(tmp_path):
    """Create a health monitor config file."""
    config = {
        "thresholds": {
            "cpu_warning": 70,
            "cpu_critical": 90,
            "memory_warning": 75,
            "memory_critical": 95,
            "disk_warning": 80,
            "disk_critical": 95,
            "swap_critical": 80,
            "temp_critical": 85,
        },
        "alert_endpoint": "https://monitor.example.com",
        "api_key": "test-key",
    }
    config_file = tmp_path / "health-config.json"
    config_file.write_text(json.dumps(config, indent=2))
    return str(config_file), config


@pytest.fixture()
def hardening_config(tmp_path):
    """Create a security hardening config file."""
    config = {
        "apparmor_profiles": [
            {"name": "stratura-supervisor", "content": "profile stratura {}"}
        ],
        "seccomp_profiles": [
            {
                "name": "default.json",
                "rules": {"defaultAction": "SCMP_ACT_ERRNO"},
            }
        ],
    }
    config_file = tmp_path / "hardening.json"
    config_file.write_text(json.dumps(config, indent=2))
    return str(config_file), config
