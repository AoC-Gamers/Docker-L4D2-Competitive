#!/bin/bash
# Script: ssh.sh
# Descripción: Configura el servicio SSH en el contenedor.

sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i "s/#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config
service ssh start
