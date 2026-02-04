# StraturaOS API Reference

## Overview

StraturaOS provides a RESTful API for device management, monitoring, and updates.

**Base URL**: `https://<device-ip>:48484`

**Source**: `meta-custom-pi-os/recipes-core/stratura-api/`

---

## Authentication

All API requests require authentication via API key.

**Header**: `X-API-Key: <your-api-key>`

```bash
curl -k -H "X-API-Key: your-api-key" https://device:48484/v1/status
```

### API Key Management

API keys are stored in `/etc/stratura/api-keys.json`:

```json
{
  "keys": [
    {
      "key": "sk_live_xxxxxxxxxxxx",
      "name": "admin",
      "permissions": ["read", "write", "admin"]
    }
  ]
}
```

---

## Endpoints

### Device Status

#### GET `/v1/status`

Returns current device status and system information.

**Response**:
```json
{
  "status": "ok",
  "device_id": "stratura-xxxx-xxxx",
  "hostname": "stratura-device",
  "uptime": 86400,
  "version": "1.0.0",
  "boot_slot": "A",
  "system": {
    "cpu_usage": 15.2,
    "memory_used": 512000000,
    "memory_total": 4096000000,
    "disk_used": 2000000000,
    "disk_total": 16000000000,
    "temperature": 45.5
  },
  "network": {
    "interface": "eth0",
    "ip_address": "192.168.1.100",
    "connected": true
  },
  "update": {
    "state": "idle",
    "available": false,
    "current_version": "1.0.0"
  }
}
```

---

### Update Management

#### GET `/v1/update`

Check for available updates.

**Response**:
```json
{
  "available": true,
  "current_version": "1.0.0",
  "latest_version": "1.1.0",
  "changelog": "Bug fixes and improvements",
  "size_bytes": 256000000
}
```

#### POST `/v1/update`

Trigger a system update.

**Request Body**:
```json
{
  "version": "1.1.0",
  "force": false
}
```

**Response**:
```json
{
  "status": "downloading",
  "message": "Update started",
  "estimated_time": 300
}
```

#### GET `/v1/update/status`

Get current update progress.

**Response**:
```json
{
  "state": "downloading",
  "progress": 45,
  "current_step": "Downloading update bundle",
  "error": null
}
```

**Update States**:
| State | Description |
|-------|-------------|
| `idle` | No update in progress |
| `checking` | Checking for updates |
| `downloading` | Downloading update bundle |
| `verifying` | Verifying signature and integrity |
| `installing` | Installing to inactive partition |
| `rebooting` | Rebooting to new partition |
| `failed` | Update failed (rollback available) |

#### POST `/v1/update/rollback`

Trigger rollback to previous version.

**Response**:
```json
{
  "status": "rolling_back",
  "message": "Rollback initiated"
}
```

---

### Container Management

#### GET `/v1/containers`

List all managed containers.

**Response**:
```json
{
  "containers": [
    {
      "name": "app-server",
      "image": "myregistry/app:latest",
      "status": "running",
      "health": "healthy",
      "uptime": 3600,
      "ports": {"8080": "8080"},
      "memory_usage": 128000000,
      "cpu_usage": 5.2
    },
    {
      "name": "worker",
      "image": "myregistry/worker:latest",
      "status": "running",
      "health": "healthy",
      "uptime": 3600,
      "ports": {},
      "memory_usage": 64000000,
      "cpu_usage": 2.1
    }
  ]
}
```

#### GET `/v1/containers/{name}`

Get details for a specific container.

**Response**:
```json
{
  "name": "app-server",
  "image": "myregistry/app:latest",
  "status": "running",
  "health": "healthy",
  "created": "2024-01-15T10:30:00Z",
  "started": "2024-01-15T10:30:05Z",
  "ports": {"8080": "8080"},
  "environment": {
    "APP_ENV": "production"
  },
  "volumes": [
    "/mnt/data/app:/app/data"
  ],
  "resource_limits": {
    "memory": "512m",
    "cpu": 0.5
  }
}
```

#### POST `/v1/containers/{name}/restart`

Restart a specific container.

**Response**:
```json
{
  "status": "restarting",
  "message": "Container restart initiated"
}
```

#### POST `/v1/containers/{name}/stop`

Stop a specific container.

**Response**:
```json
{
  "status": "stopped",
  "message": "Container stopped"
}
```

#### POST `/v1/containers/{name}/start`

Start a stopped container.

**Response**:
```json
{
  "status": "starting",
  "message": "Container start initiated"
}
```

#### GET `/v1/containers/{name}/logs`

Get container logs.

**Query Parameters**:
- `lines` (int): Number of lines to return (default: 100)
- `since` (string): Return logs since timestamp

**Response**:
```json
{
  "container": "app-server",
  "logs": [
    {"timestamp": "2024-01-15T10:30:05Z", "message": "Server starting..."},
    {"timestamp": "2024-01-15T10:30:06Z", "message": "Listening on port 8080"}
  ]
}
```

---

### System Operations

#### POST `/v1/system/reboot`

Reboot the device.

**Response**:
```json
{
  "status": "rebooting",
  "message": "System will reboot in 5 seconds"
}
```

#### GET `/v1/system/health`

Get system health check results.

**Response**:
```json
{
  "healthy": true,
  "checks": {
    "disk": {"status": "ok", "message": "Sufficient disk space"},
    "memory": {"status": "ok", "message": "Memory usage normal"},
    "network": {"status": "ok", "message": "Network connected"},
    "containers": {"status": "ok", "message": "All containers healthy"}
  }
}
```

#### GET `/v1/system/logs`

Get system logs.

**Query Parameters**:
- `service` (string): Filter by service name
- `lines` (int): Number of lines (default: 100)
- `level` (string): Filter by level (error, warn, info, debug)

**Response**:
```json
{
  "logs": [
    {
      "timestamp": "2024-01-15T10:30:00Z",
      "service": "stratura-supervisor",
      "level": "info",
      "message": "Supervisor started"
    }
  ]
}
```

---

### Configuration

#### GET `/v1/config`

Get current configuration.

**Response**:
```json
{
  "network": {
    "hostname": "stratura-device",
    "interface": "eth0",
    "dhcp": true
  },
  "update": {
    "auto_update": false,
    "check_interval": 3600
  },
  "security": {
    "selinux_enabled": true,
    "apparmor_enabled": true
  }
}
```

#### PATCH `/v1/config`

Update configuration (partial update).

**Request Body**:
```json
{
  "update": {
    "auto_update": true
  }
}
```

**Response**:
```json
{
  "status": "updated",
  "message": "Configuration updated",
  "requires_reboot": false
}
```

---

## Error Responses

All errors follow a standard format:

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid API key",
    "details": null
  }
}
```

### Error Codes

| HTTP Status | Code | Description |
|-------------|------|-------------|
| 400 | `BAD_REQUEST` | Invalid request body |
| 401 | `UNAUTHORIZED` | Missing or invalid API key |
| 403 | `FORBIDDEN` | Insufficient permissions |
| 404 | `NOT_FOUND` | Resource not found |
| 409 | `CONFLICT` | Operation conflicts with current state |
| 500 | `INTERNAL_ERROR` | Internal server error |
| 503 | `SERVICE_UNAVAILABLE` | Service temporarily unavailable |

---

## Rate Limiting

API requests are rate-limited to prevent abuse:

- **Default**: 100 requests per minute
- **Update endpoints**: 10 requests per minute

Rate limit headers in response:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1705320000
```

---

## Security

### TLS Requirements

- All connections must use HTTPS (TLS 1.2+)
- Self-signed certificates are used by default
- Custom certificates can be installed at `/etc/stratura/certs/`

### Example with curl

```bash
# With certificate verification disabled (development)
curl -k -H "X-API-Key: your-key" https://device:48484/v1/status

# With custom CA certificate (production)
curl --cacert /path/to/ca.crt -H "X-API-Key: your-key" https://device:48484/v1/status
```

### Example with Python

```python
import requests

API_KEY = "your-api-key"
BASE_URL = "https://device:48484"

headers = {"X-API-Key": API_KEY}
response = requests.get(f"{BASE_URL}/v1/status", headers=headers, verify=False)
print(response.json())
```
