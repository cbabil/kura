# Building straturaOS

## Development Environment Setup

1. Clone required repositories:
   ```bash
   git clone git://git.yoctoproject.org/poky -b kirkstone
   git clone git://git.yoctoproject.org/meta-raspberrypi -b kirkstone
   git clone git://git.openembedded.org/meta-openembedded -b kirkstone
   git clone https://github.com/your-org/meta-stratura
   ```

2. Setup build environment:
   ```bash
   source poky/oe-init-build-env build
   ```

3. Configure layers in `conf/bblayers.conf`:
   ```bash
   BBLAYERS ?= " \
     ${TOPDIR}/../poky/meta \
     ${TOPDIR}/../poky/meta-poky \
     ${TOPDIR}/../poky/meta-yocto-bsp \
     ${TOPDIR}/../meta-raspberrypi \
     ${TOPDIR}/../meta-openembedded/meta-oe \
     ${TOPDIR}/../meta-openembedded/meta-python \
     ${TOPDIR}/../meta-openembedded/meta-networking \
     ${TOPDIR}/../meta-stratura \
     "
   ```

## Building Images

### Development Image
   ```bash
   bitbake stratura-image-dev
   ```

### Production Image
   ```bash
   bitbake stratura-image-prod
   ```

### Update Bundle
   ```bash
   bitbake stratura-update-bundle
   ```

## Customization

### Adding Packages
Edit `conf/local.conf`:
   ```bash
   IMAGE_INSTALL_append = " package-name"
   ```

### Modifying Features
   ```bash
   DISTRO_FEATURES_append = " feature-name"
   ```

### Custom Configuration
Create a custom layer:
   ```bash
   bitbake-layers create-layer meta-custom
   ```

## Testing

### QEMU Testing
   ```bash
   runqemu qemuarm64 stratura-image-dev
   ```

### Hardware Testing
   ```bash
   sudo dd if=tmp/deploy/images/raspberrypi5/stratura-image-prod.wic of=/dev/sdX bs=4M
   ```

## Debugging

### Runtime Logs
- System logs: `/var/log/stratura/`
- Container logs: `docker logs container-name`
- Update logs: `/var/log/stratura/update.log`

### Build Logs
- Build logs: `tmp/work/*/*/temp/log.do_*`
- Task logs: `tmp/work/*/*/temp/run.do_*`