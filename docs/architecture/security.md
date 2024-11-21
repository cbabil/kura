# Security Hardening

## Overview
straturaOS implements multiple layers of security to protect the system and data.

## Boot Security
- **Secure Boot**: Ensures only signed bootloaders and kernels are executed.
- **TPM Integration**: Uses TPM for secure key storage and boot measurement.

## Runtime Security
- **SELinux**: Enforces mandatory access control policies.
- **AppArmor**: Provides application-level security profiles.
- **Seccomp**: Restricts system calls available to applications.

## Network Security
- **Firewall**: Configures iptables for network traffic control.
- **VPN Support**: Allows secure remote access.

## Update Security
- **Signed Updates**: Ensures integrity and authenticity of updates.
- **Rollback Protection**: Prevents downgrades to vulnerable versions.

## Best Practices
- Regularly update system and applications.
- Use strong, unique passwords for all accounts.
- Monitor system logs for suspicious activity.
- Regularly review and update security policies. 