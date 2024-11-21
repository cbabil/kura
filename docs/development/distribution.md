# Building straturaOS for Distribution

## Prerequisites
- Complete build environment setup from [Building Guide](building.md)
- GPG key for signing updates
- SSL certificates for API endpoints

## 1. Creating Release Build

### Configure Release Settings
Edit `conf/local.conf`:
```bash
# Disable debug features
EXTRA_IMAGE_FEATURES_remove = "debug-tweaks"

# Enable production features
INHERIT += "rm_work"
INHERIT += "image-buildinfo"
IMAGE_FEATURES += "read-only-rootfs"

# Set version information
STRATURA_OS_VERSION = "1.0.0"
STRATURA_OS_NAME = "straturaOS"
```

### Build Production Image
```bash
# Clean previous builds
bitbake -c cleanall stratura-image-prod

# Build production image
bitbake stratura-image-prod
```

## 2. Signing the Image

### Generate Keys (if not already done)
```bash
# Generate RAUC keys
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout rauc.key.pem -out rauc.cert.pem \
  -subj "/O=straturaOS/CN=rauc-signing"

# Generate API keys
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout api.key.pem -out api.cert.pem \
  -subj "/O=straturaOS/CN=api-signing"
```

### Sign the Image
```bash
# Sign bootloader
./scripts/sign-boot-partition.sh \
  tmp/deploy/images/raspberrypi5/stratura-image-prod.wic

# Create and sign update bundle
rauc bundle \
  --cert rauc.cert.pem \
  --key rauc.key.pem \
  --format verity \
  tmp/deploy/images/raspberrypi5/stratura-image-prod.raucb \
  tmp/deploy/images/raspberrypi5/stratura-image-prod.wic
```

## 3. Creating Distribution Package

### Package Structure
```
stratura-os-1.0.0/
├── images/
│   ├── stratura-image-prod.wic        # Raw image
│   └── stratura-image-prod.raucb      # Update bundle
├── certs/
│   ├── rauc-ca.cert.pem              # RAUC public certificate
│   └── api-ca.cert.pem               # API public certificate
├── tools/
│   ├── flash-tool.sh                 # Flashing script
│   └── verify-image.sh               # Verification script
└── docs/
    ├── README.md                     # Installation guide
    └── CHANGELOG.md                  # Version changes
```

### Create Distribution Package
```bash
# Create distribution directory
mkdir -p stratura-os-1.0.0/{images,certs,tools,docs}

# Copy images
cp tmp/deploy/images/raspberrypi5/stratura-image-prod.wic \
   stratura-os-1.0.0/images/
cp tmp/deploy/images/raspberrypi5/stratura-image-prod.raucb \
   stratura-os-1.0.0/images/

# Copy certificates
cp rauc.cert.pem stratura-os-1.0.0/certs/rauc-ca.cert.pem
cp api.cert.pem stratura-os-1.0.0/certs/api-ca.cert.pem

# Copy tools and documentation
cp scripts/flash-tool.sh stratura-os-1.0.0/tools/
cp scripts/verify-image.sh stratura-os-1.0.0/tools/
cp docs/README.md stratura-os-1.0.0/docs/
cp docs/CHANGELOG.md stratura-os-1.0.0/docs/

# Create archive
tar czf stratura-os-1.0.0.tar.gz stratura-os-1.0.0/
```

## 4. Verification

### Verify Image Integrity
```bash
# Verify image signature
./scripts/verify-image.sh stratura-os-1.0.0/images/stratura-image-prod.wic

# Verify update bundle
rauc verify stratura-os-1.0.0/images/stratura-image-prod.raucb
```

### Test Image in QEMU
```bash
# Run image in QEMU
./scripts/run-qemu.sh stratura-os-1.0.0/images/stratura-image-prod.wic
```

## 5. Distribution

### Create Release Notes
```bash
# Generate checksums
cd stratura-os-1.0.0
sha256sum images/* > SHA256SUMS
gpg --detach-sign --armor SHA256SUMS
```

### Upload to Distribution Server
```bash
# Upload to release server
scp stratura-os-1.0.0.tar.gz user@release-server:/path/to/releases/
scp SHA256SUMS* user@release-server:/path/to/releases/
```

## 6. Update Server Setup

### Configure Update Server
```bash
# Deploy update bundle
scp stratura-os-1.0.0/images/stratura-image-prod.raucb \
    user@update-server:/var/www/updates/

# Update manifest
ssh user@update-server "update-manifest.sh 1.0.0"
```

## Security Considerations

1. **Key Management**
   - Store signing keys securely
   - Use Hardware Security Module (HSM) for production keys
   - Implement key rotation policy

2. **Distribution Security**
   - Use HTTPS for downloads
   - Implement download rate limiting
   - Verify checksums before distribution

3. **Update Security**
   - Sign all updates
   - Implement rollback protection
   - Monitor update deployment

## Automated Release Pipeline

Create `.gitlab-ci.yml` or similar for CI/CD:

```yaml
stages:
  - build
  - test
  - sign
  - package
  - deploy

build:
  stage: build
  script:
    - bitbake stratura-image-prod

test:
  stage: test
  script:
    - ./scripts/run-tests.sh

sign:
  stage: sign
  script:
    - ./scripts/sign-images.sh

package:
  stage: package
  script:
    - ./scripts/create-distribution.sh

deploy:
  stage: deploy
  script:
    - ./scripts/deploy-release.sh
  only:
    - tags
``` 