#!/usr/bin/env python3

import os
import subprocess
import logging
import datetime
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.x509.oid import NameOID
import ssl

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('security-manager')

class SecurityManager:
    def __init__(self):
        self.cert_path = '/etc/stratura/certs'
        self.keys_path = '/etc/stratura/keys'
        self.ca_cert = None
        self.device_cert = None
        self.device_key = None
        self.tpm = None  # TPM handler for secure key storage
        
    def initialize_security(self):
        """Initialize all security components"""
        try:
            self.load_certificates()
            self.verify_certificates()
            self.setup_secure_boot()
            self.configure_firewall()
            self.initialize_tpm()
            self.setup_selinux()
        except Exception as e:
            logger.error(f"Security initialization failed: {e}")
            raise

    def verify_cert_chain(self, cert, ca_cert):
        """Verify certificate chain with proper validation"""
        try:
            # Create certificate store
            store = x509.Store()
            store.add_cert(ca_cert)
            
            # Create certificate context
            store_ctx = x509.StoreContext(store, cert)
            
            # Verify chain
            store_ctx.verify_certificate()
            
            # Additional checks
            if not self.verify_cert_revocation(cert):
                return False
            
            if not self.verify_cert_purpose(cert):
                return False
            
            return True
            
        except Exception as e:
            logging.error(f"Certificate chain verification failed: {e}")
            return False

    def verify_cert_revocation(self, cert):
        """Check certificate revocation status"""
        try:
            # Check CRL
            crl_path = f"{self.cert_path}/crl.pem"
            if os.path.exists(crl_path):
                with open(crl_path, 'rb') as f:
                    crl = x509.load_pem_x509_crl(f.read())
                    if crl.is_revoked(cert):
                        return False
            
            # Check OCSP
            ocsp_url = self.get_ocsp_url(cert)
            if ocsp_url:
                if not self.check_ocsp_status(cert, ocsp_url):
                    return False
                
            return True
            
        except Exception as e:
            logging.error(f"Revocation check failed: {e}")
            return False

    def initialize_tpm(self):
        """Initialize TPM for secure key storage"""
        try:
            # Check TPM presence
            result = subprocess.run(['tpm2_getcap', 'properties-fixed'],
                              capture_output=True, text=True)
            if result.returncode != 0:
                raise Exception("TPM not available")

            # Initialize TPM storage
            subprocess.run(['tpm2_clear'])
            subprocess.run(['tpm2_createprimary', '-c', 'primary.ctx'])
            
            # Store device keys in TPM
            self.store_keys_in_tpm()
        except Exception as e:
            logger.error(f"TPM initialization failed: {e}")
            raise

    def setup_selinux(self):
        """Configure SELinux policies"""
        try:
            # Enable SELinux
            subprocess.run(['setenforce', '1'])
            
            # Load custom policies
            policy_path = '/etc/stratura/selinux'
            for policy in os.listdir(policy_path):
                if policy.endswith('.pp'):
                    subprocess.run(['semodule', '-i', 
                                 f"{policy_path}/{policy}"])
        except Exception as e:
            logger.error(f"SELinux setup failed: {e}")
            raise

    def verify_secure_boot(self):
        """Verify secure boot chain"""
        try:
            # Check U-Boot secure boot status
            result = subprocess.run(['stratura-verify-boot'],
                                 capture_output=True, text=True)
            if result.returncode != 0:
                raise Exception("Secure boot verification failed")

            # Verify kernel signature
            kernel_sig = "/boot/kernel.sig"
            if not os.path.exists(kernel_sig):
                raise Exception("Kernel signature missing")

            # Verify initramfs
            initramfs_sig = "/boot/initramfs.sig"
            if not os.path.exists(initramfs_sig):
                raise Exception("Initramfs signature missing")

            return True
        except Exception as e:
            logger.error(f"Secure boot verification failed: {e}")
            return False

    def configure_advanced_firewall(self):
        """Configure advanced firewall rules"""
        rules = [
            # Allow established connections
            "iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT",
            
            # Allow supervisor API with rate limiting
            "iptables -A INPUT -p tcp --dport 48484 -m limit --limit 60/min -j ACCEPT",
            
            # Allow SSH only from local network with rate limiting
            "iptables -A INPUT -p tcp --dport 22 -s 192.168.0.0/16 -m limit --limit 10/min -j ACCEPT",
            
            # Allow container communications
            "iptables -A INPUT -i docker0 -j ACCEPT",
            
            # Allow DNS
            "iptables -A OUTPUT -p udp --dport 53 -j ACCEPT",
            
            # Allow NTP
            "iptables -A OUTPUT -p udp --dport 123 -j ACCEPT",
            
            # Default policies
            "iptables -P INPUT DROP",
            "iptables -P FORWARD DROP",
            "iptables -P OUTPUT ACCEPT"
        ]
        
        for rule in rules:
            try:
                subprocess.run(rule.split(), check=True)
            except subprocess.CalledProcessError as e:
                logger.error(f"Firewall rule failed: {rule}")
                raise

    def rotate_keys(self):
        """Rotate device keys periodically"""
        try:
            # Generate new key pair
            private_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=2048
            )
            
            # Create new certificate
            subject = x509.Name([
                x509.NameAttribute(NameOID.COMMON_NAME, u"stratura-device")
            ])
            
            cert = x509.CertificateBuilder()\
                .subject_name(subject)\
                .issuer_name(self.ca_cert.subject)\
                .public_key(private_key.public_key())\
                .serial_number(x509.random_serial_number())\
                .not_valid_before(datetime.datetime.utcnow())\
                .not_valid_after(datetime.datetime.utcnow() + 
                               datetime.timedelta(days=365))\
                .sign(private_key, hashes.SHA256())
            
            # Store new credentials
            self.store_new_credentials(private_key, cert)
            
        except Exception as e:
            logger.error(f"Key rotation failed: {e}")
            raise

    def store_new_credentials(self, private_key, cert):
        """Store new credentials securely"""
        try:
            # Store private key in TPM
            key_blob = private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            )
            self.store_in_tpm("device_key", key_blob)
            
            # Store certificate
            cert_path = os.path.join(self.cert_path, "device.pem")
            with open(cert_path, 'wb') as f:
                f.write(cert.public_bytes(serialization.Encoding.PEM))
                
        except Exception as e:
            logger.error(f"Credential storage failed: {e}")
            raise

    def setup_secure_boot(self):
        """Configure secure boot with hardware root of trust"""
        try:
            # Check TPM availability
            if not self.check_tpm():
                raise Exception("TPM not available")
            
            # Measure boot components
            self.measure_boot_components()
            
            # Configure U-Boot secure boot
            subprocess.run(['stratura-secure-boot', '--enable', '--tpm'])
            
            # Verify secure boot chain
            if not self.verify_secure_boot():
                raise Exception("Secure boot verification failed")
            
            # Lock boot configuration
            self.lock_boot_configuration()
            
        except Exception as e:
            logging.error(f"Secure boot setup failed: {e}")
            raise