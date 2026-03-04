#!/usr/bin/env bash
set -euo pipefail

echo "======================================"
echo " Docker + Docker Compose installer"
echo "======================================"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script only supports Linux."
  exit 1
fi

# Detect distro
if ! command -v apt >/dev/null 2>&1; then
  echo "This script currently supports Ubuntu/Debian (apt)."
  exit 1
fi

echo
echo "Step 1: Remove conflicting docker packages (if present)"
sudo apt remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true

echo
echo "Step 2: Install prerequisites"
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

echo
echo "Step 3: Configure Docker official repository"
sudo install -m 0755 -d /etc/apt/keyrings

if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

sudo chmod a+r /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

echo \
"deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
| sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

echo
echo "Step 4: Install Docker Engine + Compose + Buildx"
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo
echo "Step 5: Enable and start Docker"
sudo systemctl enable docker >/dev/null
sudo systemctl start docker

echo
echo "Step 6: Add current user to docker group"
if ! groups "$USER" | grep -q docker; then
  sudo usermod -aG docker "$USER"
  GROUP_ADDED=true
else
  GROUP_ADDED=false
fi

echo
echo "Step 7: Verify installation"
docker --version
docker compose version
docker buildx version

echo
echo "Step 8: Running hello-world test"
if docker run --rm hello-world >/dev/null 2>&1; then
  echo "Docker hello-world succeeded."
else
  echo "Retrying with sudo (group change may require new login)..."
  sudo docker run --rm hello-world
fi

echo
echo "======================================"
echo " Docker installation complete"
echo "======================================"

if [[ "$GROUP_ADDED" == true ]]; then
  echo
  echo "NOTE:"
  echo "You were added to the 'docker' group."
  echo "Run:"
  echo
  echo "  newgrp docker"
  echo
  echo "or logout/login before using docker without sudo."
fi
