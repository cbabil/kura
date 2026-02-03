#!/usr/bin/env python3

import os
import subprocess
import logging
import json
from typing import Dict, List
from pathlib import Path

class SecurityHardening:
    def __init__(self):
        self.config_path = '/etc/stratura/security/hardening.json'
        self.load_config()
        
    def load_config(self):
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
            
    def harden_system(self):
        """Apply system hardening measures"""
        try:
            self.configure_kernel_parameters()
            self.setup_apparmor_profiles()
            self.configure_seccomp()
            self.harden_ssh()
            self.setup_auditd()
            self.configure_firewall()
            self.harden_filesystem()
            
        except Exception as e:
            logging.error(f"System hardening failed: {e}")
            raise

    def configure_kernel_parameters(self):
        """Configure secure kernel parameters"""
        sysctl_params = {
            'kernel.kptr_restrict': 2,
            'kernel.dmesg_restrict': 1,
            'kernel.perf_event_paranoid': 3,
            'kernel.yama.ptrace_scope': 1,
            'net.ipv4.conf.all.accept_redirects': 0,
            'net.ipv4.conf.all.accept_source_route': 0,
            'net.ipv4.conf.all.rp_filter': 1,
            'net.ipv4.tcp_syncookies': 1
        }
        
        for param, value in sysctl_params.items():
            subprocess.run(['sysctl', '-w', f"{param}={value}"])

    def setup_apparmor_profiles(self):
        """Setup AppArmor profiles"""
        profiles_dir = '/etc/apparmor.d/stratura'
        os.makedirs(profiles_dir, exist_ok=True)
        
        # Install base profiles
        for profile in self.config['apparmor_profiles']:
            profile_path = os.path.join(profiles_dir, profile['name'])
            with open(profile_path, 'w') as f:
                f.write(profile['content'])
                
        # Reload AppArmor
        subprocess.run(['apparmor_parser', '-r', '-T', profiles_dir])

    def configure_seccomp(self):
        """Configure Seccomp profiles"""
        seccomp_dir = '/etc/stratura/security/seccomp'
        os.makedirs(seccomp_dir, exist_ok=True)
        
        for profile in self.config['seccomp_profiles']:
            profile_path = os.path.join(seccomp_dir, profile['name'])
            with open(profile_path, 'w') as f:
                json.dump(profile['rules'], f)

    def harden_ssh(self):
        """Harden SSH configuration"""
        ssh_config = {
            'PermitRootLogin': 'no',
            'PasswordAuthentication': 'no',
            'X11Forwarding': 'no',
            'MaxAuthTries': '3',
            'AllowAgentForwarding': 'no',
            'AllowTcpForwarding': 'no',
            'PrintLastLog': 'yes',
            'ClientAliveInterval': '300',
            'ClientAliveCountMax': '2'
        }
        
        config_path = '/etc/ssh/sshd_config'
        with open(config_path, 'a') as f:
            for key, value in ssh_config.items():
                f.write(f"\n{key} {value}")
                
        subprocess.run(['systemctl', 'restart', 'sshd'])

    def setup_auditd(self):
        """Configure system auditing"""
        audit_rules = [
            '-w /etc/passwd -p wa -k identity',
            '-w /etc/group -p wa -k identity',
            '-w /etc/shadow -p wa -k identity',
            '-w /etc/sudoers -p wa -k sudo_actions',
            '-w /var/log/auth.log -p wa -k auth_logs',
            '-a always,exit -F arch=b64 -S execve -k exec_calls'
        ]
        
        rules_path = '/etc/audit/rules.d/stratura.rules'
        with open(rules_path, 'w') as f:
            for rule in audit_rules:
                f.write(f"{rule}\n")
                
        subprocess.run(['auditctl', '-R', rules_path])

    def harden_filesystem(self):
        """Harden filesystem permissions and mount options"""
        mount_options = {
            '/tmp': 'noexec,nosuid,nodev',
            '/var/tmp': 'noexec,nosuid,nodev',
            '/dev/shm': 'noexec,nosuid,nodev',
            '/home': 'nodev'
        }
        
        for mount_point, options in mount_options.items():
            subprocess.run(['mount', '-o', 'remount,' + options, mount_point])
            
        # Update fstab
        self.update_fstab(mount_options)

    def update_fstab(self, mount_options: Dict[str, str]):
        """Update filesystem mount options in fstab"""
        fstab_path = '/etc/fstab'
        new_fstab = []
        
        with open(fstab_path, 'r') as f:
            for line in f:
                if not line.strip() or line.startswith('#'):
                    new_fstab.append(line)
                    continue
                    
                parts = line.split()
                mount_point = parts[1]
                
                if mount_point in mount_options:
                    parts[3] = mount_options[mount_point]
                    line = '\t'.join(parts) + '\n'
                    
                new_fstab.append(line)
                
        with open(fstab_path, 'w') as f:
            f.writelines(new_fstab) 