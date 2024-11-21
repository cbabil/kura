#!/usr/bin/env python3

from flask import Flask, request, send_file, jsonify
import os
import json
import logging
from functools import wraps

app = Flask(__name__)

# Configuration
UPDATES_DIR = '/var/www/updates'
MANIFEST_FILE = '/var/www/updates/manifest.json'
API_KEY = os.environ.get('STRATURA_API_KEY')

def require_api_key(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        key = request.headers.get('X-API-Key')
        if key != API_KEY:
            return jsonify({'error': 'Invalid API key'}), 403
        return f(*args, **kwargs)
    return decorated

@app.route('/v1/updates/latest', methods=['GET'])
@require_api_key
def get_latest_update():
    try:
        with open(MANIFEST_FILE, 'r') as f:
            manifest = json.load(f)
        return jsonify(manifest['latest'])
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/v1/updates/<version>', methods=['GET'])
@require_api_key
def download_update(version):
    try:
        update_file = os.path.join(UPDATES_DIR, f'stratura-os-{version}.raucb')
        if not os.path.exists(update_file):
            return jsonify({'error': 'Update not found'}), 404
        return send_file(update_file)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/v1/updates', methods=['POST'])
@require_api_key
def upload_update():
    try:
        if 'file' not in request.files:
            return jsonify({'error': 'No file provided'}), 400
            
        file = request.files['file']
        version = request.form.get('version')
        
        if not version:
            return jsonify({'error': 'No version provided'}), 400
            
        # Save update file
        update_file = os.path.join(UPDATES_DIR, f'stratura-os-{version}.raucb')
        file.save(update_file)
        
        # Update manifest
        with open(MANIFEST_FILE, 'r') as f:
            manifest = json.load(f)
            
        manifest['latest'] = {
            'version': version,
            'file': f'stratura-os-{version}.raucb',
            'checksum': calculate_checksum(update_file)
        }
        
        with open(MANIFEST_FILE, 'w') as f:
            json.dump(manifest, f, indent=2)
            
        return jsonify({'status': 'success'})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

def calculate_checksum(file_path):
    import hashlib
    sha256_hash = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for byte_block in iter(lambda: f.read(4096), b''):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, ssl_context='adhoc') 