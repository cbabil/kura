# API Documentation

## Overview
straturaOS provides a RESTful API for device management, monitoring, and updates.

## Authentication
- API Key: Use `X-API-Key` header for authentication.

## Endpoints

### Device Status
- **GET** `/v1/status`
  - Returns current device status.

### Update Management
- **POST** `/v1/update`
  - Triggers a system update.
  - Parameters: `version` (string)

### Container Management
- **GET** `/v1/containers`
  - Returns status of all managed containers.

- **POST** `/v1/containers/{name}/restart`
  - Restarts a specified container.
  - Parameters: `name` (string)

## Error Handling
- 403 Forbidden: Invalid API key.
- 500 Internal Server Error: General server error.

## Security
- All endpoints require SSL/TLS.
- Ensure API key is kept secure. 