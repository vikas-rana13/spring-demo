#!/bin/bash
# ==============================================================================
# start-service.sh - Secure Container Lifecycle Management & Rollouts (Docker Hub)
# ==============================================================================
# Strict mode: exit on error (-e), unset variables (-u), and pipeline failures (-o)
set -euo pipefail

# Enterprise parameters passed dynamically from Jenkins SSH
DOCKER_USER="${DOCKER_USER}"
DOCKER_PASSWORD="${DOCKER_PASSWORD}"
IMAGE_NAME="${IMAGE_NAME}"
IMAGE_TAG="${IMAGE_TAG}"
PORT="${APP_PORT:-8080}"

CONTAINER_NAME="spring-boot-app"
FULL_IMAGE_PATH="${DOCKER_USER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "============================================="
echo "=== Container Lifecycle Management        ==="
echo "=== Deploying Image: ${FULL_IMAGE_PATH} ==="
echo "=== Application Port: ${PORT}             ==="
echo "============================================="

# 1. Authenticate against Docker Hub dynamically
echo "[INFO] Authenticating against Docker Hub..."
echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USER}" --password-stdin

# 2. Pull the specific version-tagged image from Docker Hub
echo "[INFO] Pulling container image from Docker Hub..."
docker pull "${FULL_IMAGE_PATH}"

# 3. Stop and remove the old running container version (if it exists)
echo "[INFO] Terminating previous container release..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    docker stop "${CONTAINER_NAME}" || true
    docker rm "${CONTAINER_NAME}" || true
    echo "[INFO] Previous container cleared."
fi

# 4. Launch the new isolated container sandbox
echo "[INFO] Initializing new release..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${PORT}:${PORT}" \
  -e PORT="${PORT}" \
  --restart unless-stopped \
  "${FULL_IMAGE_PATH}"

# 5. Active Health Check / Verification
echo "[INFO] Verifying container initialization status..."
sleep 5
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo "=== SUCCESS: Container is live on Port ${PORT}! ==="
    # Clean up unused old cached images to prevent host disk exhaustion
    echo "[INFO] Pruning obsolete Docker cache..."
    docker image prune -f
else
    echo "=== ERROR: Container failed to start. Printing container logs: ===" >&2
    docker logs "${CONTAINER_NAME}"
    exit 1
fi
