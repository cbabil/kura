# Troubleshooting Guide

## Common Issues

### Build Failures
- **Symptom**: Bitbake fails with missing dependencies.
  - **Solution**: Ensure all required packages are installed on the host system.

### Boot Issues
- **Symptom**: Device does not boot after flashing.
  - **Solution**: Verify SD card integrity and ensure correct image is used.

### Network Connectivity
- **Symptom**: Device cannot connect to network.
  - **Solution**: Check `/etc/NetworkManager/conf.d/00-stratura-network.conf` for correct settings.

### Update Failures
- **Symptom**: Updates fail to install.
  - **Solution**: Check RAUC logs in `/var/log/stratura/update.log` for errors.

### Container Issues
- **Symptom**: Containers fail to start.
  - **Solution**: Check Docker logs using `docker logs container-name`.

## Debugging Tips

### Logs
- System logs: `/var/log/stratura/`
- Update logs: `/var/log/stratura/update.log`
- Container logs: `docker logs container-name`

### Commands
- Check system status: `systemctl status`
- Check network status: `nmcli device status`
- Check Docker status: `docker ps -a`

## Support
- For further assistance, contact support at support@straturaos.com. 