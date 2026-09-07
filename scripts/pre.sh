#!/bin/bash
# ==============================================================================
# pre.sh - Hardened Host OS Container Setup (AWS AL2023)
# ==============================================================================
# Strict mode: exit on error (-e), unset variables (-u), and pipeline failures (-o)
set -euo pipefail

echo "================================================="
echo "=== Running Docker Host Bootstrap (pre.sh)    ==="
echo "================================================="

# 1. Update package repository and install Docker Engine
echo "[INFO] Installing Docker Engine via DNF..."
sudo dnf update -y
sudo dnf install docker -y

# 2. Enable and start the Docker background system service
echo "[INFO] Starting and enabling Docker Daemon..."
sudo systemctl enable --now docker

# 3. Grant the ec2-user permission to run docker commands without sudo
# This allows our deployment script (running as ec2-user) to talk to the Docker socket.
echo "[INFO] Adding ec2-user to the docker group..."
sudo usermod -aG docker ec2-user

echo "=== Docker Host Bootstrap Complete! ==="
