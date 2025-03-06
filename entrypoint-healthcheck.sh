#!/bin/bash
set -e

SSH_PORT=${SSH_PORT:-22}

nc -zv localhost $SSH_PORT
if [ $? -eq 0 ]; then
    echo "SSH port $SSH_PORT is open"
    exit 0
else
    echo "SSH port $SSH_PORT is closed"
    exit 1
fi