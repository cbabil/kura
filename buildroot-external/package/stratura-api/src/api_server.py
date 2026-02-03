#!/usr/bin/env python3

from fastapi import FastAPI, HTTPException, Security
from fastapi.security import APIKeyHeader
from typing import Dict, List
import uvicorn
import logging
import json
import os
from datetime import datetime
from stratura.update import UpdateWorkflow
from stratura.containers import ContainerManager

app = FastAPI(title="straturaOS API")
api_key_header = APIKeyHeader(name="X-API-Key")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("stratura-api")

class DeviceAPI:
    def __init__(self):
        self.config_path = '/etc/stratura/api-config.json'
        self.load_config()
        
    def load_config(self):
        with open(self.config_path) as f:
            self.config = json.load(f)
            
    async def verify_api_key(self, api_key: str = Security(api_key_header)):
        if api_key != self.config['api_key']:
            raise HTTPException(status_code=403, detail="Invalid API key")
        return api_key

@app.get("/v1/status")
async def get_status():
    """Get device status"""
    try:
        with open('/var/lib/stratura/device-state.json') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to get status: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/v1/update")
async def trigger_update(version: str):
    """Trigger system update"""
    try:
        # Validate version
        if not version.strip():
            raise ValueError("Invalid version")
            
        # Trigger update
        update_manager = UpdateWorkflow()
        await update_manager.trigger_update(version)
        
        return {"status": "Update triggered", "version": version}
        
    except Exception as e:
        logger.error(f"Update failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/v1/containers")
async def get_containers():
    """Get container status"""
    try:
        container_manager = ContainerManager()
        return container_manager.health_check()
    except Exception as e:
        logger.error(f"Failed to get container status: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/v1/containers/{name}/restart")
async def restart_container(name: str):
    """Restart container"""
    try:
        container_manager = ContainerManager()
        container_manager.restart_container(name)
        return {"status": "Container restarted", "name": name}
    except Exception as e:
        logger.error(f"Failed to restart container: {e}")
        raise HTTPException(status_code=500, detail=str(e))

def start_server():
    """Start API server"""
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=48484,
        ssl_keyfile="/etc/stratura/certs/api-key.pem",
        ssl_certfile="/etc/stratura/certs/api-cert.pem"
    )

if __name__ == "__main__":
    start_server() 