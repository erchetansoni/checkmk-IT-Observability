#!/usr/bin/env bash
set -euo pipefail

#########################################
# CONFIGURATION
#########################################

PROJECT_DIR="/home/chetan/OT-Monitoring"

IMAGE_FILE="images.tar.gz"

COMPOSE_FILE="docker-compose.yaml"

# Single-file bind-mount sources that MUST exist as real files.
# If any is missing, Docker would create it as an empty directory
# and the container would silently run with default config.
REQUIRED_FILES=(
    "traefik/tls.yaml"
    "traefik/certs/wildcard_.avgol.com.crt"
    "traefik/certs/wildcard_.avgol.com.key"
)

#########################################

cd "$PROJECT_DIR"

#########################################
# PRE-FLIGHT CHECKS
#########################################

echo "======================================"
echo "Pre-flight checks..."
echo "======================================"

# Warn if no .env — stack will fall back to built-in simulation defaults
if [[ ! -f .env ]]; then
    echo "⚠ WARNING: no .env found — using built-in simulation defaults"
    echo "  (host.docker.internal PLC IPs, default Grafana password, etc.)"
fi

# Verify single-file bind-mount sources exist as regular files
for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo ""
        echo "ERROR: expected config file missing or not a regular file:"
        echo "  $f"
        echo ""
        echo "Docker would create this as an empty DIRECTORY and the container"
        echo "would run with default config. Fix the bundle and re-run."
        exit 1
    fi
done
echo "✔ all required config files present"

#########################################
# LOAD IMAGES
#########################################

echo ""
echo "======================================"
echo "Loading Docker Images..."
echo "======================================"

if [[ "$IMAGE_FILE" == *.gz ]]; then
    gunzip -c "$IMAGE_FILE" | docker load
else
    docker load -i "$IMAGE_FILE"
fi

#########################################
# START STACK
#########################################

echo ""
echo "Starting Docker Compose..."

docker compose \
    -f "$COMPOSE_FILE" \
    up -d

#########################################
# DONE
#########################################

echo ""
echo "Deployment Finished."

echo ""
docker ps
