#!/bin/bash
# Script: ssh.sh
# Description: Configures the SSH service in the container, generates host keys (RSA, ECDSA, and ED25519),
# and updates the SSH configuration to use a persistent directory (/data/ssh). It also enables or disables
# password authentication based on the LGSM_PASSWORD variable.

if [ ! -d /data/ssh ]; then
    mkdir -p /data/ssh
fi

if [ ! -f /data/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -t rsa -b 4096 -f /data/ssh/ssh_host_rsa_key -N ''
fi

if [ ! -f /data/ssh/ssh_host_ecdsa_key ]; then
    ssh-keygen -t ecdsa -f /data/ssh/ssh_host_ecdsa_key -N ''
fi

if [ ! -f /data/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f /data/ssh/ssh_host_ed25519_key -N ''
fi

sed -i 's|#HostKey /etc/ssh/ssh_host_rsa_key|HostKey /data/ssh/ssh_host_rsa_key|' /etc/ssh/sshd_config
sed -i 's|#HostKey /etc/ssh/ssh_host_ecdsa_key|HostKey /data/ssh/ssh_host_ecdsa_key|' /etc/ssh/sshd_config
sed -i 's|#HostKey /etc/ssh/ssh_host_ed25519_key|HostKey /data/ssh/ssh_host_ed25519_key|' /etc/ssh/sshd_config

# Configure password authentication based on the LGSM_PASSWORD variable:
# If LGSM_PASSWORD has a value, enable PasswordAuthentication.
# If it is empty, disable it.
if [ -n "${LGSM_PASSWORD}" ]; then
    sed -i 's|#PasswordAuthentication yes|PasswordAuthentication yes|' /etc/ssh/sshd_config
else
    sed -i 's|#PasswordAuthentication yes|PasswordAuthentication no|' /etc/ssh/sshd_config
fi

sed -i "s|#Port 22|Port ${SSH_PORT}|" /etc/ssh/sshd_config

# Start the SSH service
service ssh start
