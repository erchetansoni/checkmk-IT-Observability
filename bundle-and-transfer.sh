#!/usr/bin/env bash
set -Eeuo pipefail

##############################################
# CONFIGURATION
##############################################

# Docker Compose file
COMPOSE_FILE="docker-compose.yaml"

# Bundle directory
BUNDLE_DIR="./OT-Monitoring_bundle"

# Archive name (WITHOUT extension)
ARCHIVE_NAME="images"

# Compress archive?
COMPRESS=true

# Remove old bundle before creating a new one
CLEAN_BUNDLE=true

# Remote Server
REMOTE_USER="chetan"
REMOTE_HOST="172.20.64.101"
REMOTE_PATH="/home/chetan/OT-Monitoring"

##############################################
# FILES TO COPY
##############################################

FILES_TO_COPY=(
    "docker-compose.yaml"
    "deploy-on-server.sh"
)

# Subdirectories to copy
# Example: 

# DIRS_TO_COPY=(
#     "mosquitto"
#     "telegraf"
#     "timescaledb"
#     "pgbouncer"
#     "grafana"
# )

DIRS_TO_COPY=(
    "traefik"
)

REQUIRED_FILES=(
    "traefik/traefik.yaml"
    "traefik/dynamic/tls.yaml"
    "traefik/dynamic/in-ot-monitoring.avgol.com.yaml"
    "traefik/certs/wildcard_.avgol.com.crt"
    "traefik/certs/wildcard_.avgol.com.key"
)

##############################################
# CHECK DEPENDENCIES
##############################################

for CMD in docker ssh scp
do
    command -v "$CMD" >/dev/null || {
        echo "ERROR: '$CMD' is not installed."
        exit 1
    }
done

docker compose version >/dev/null

for FILE in "${REQUIRED_FILES[@]}"
do
    if [ ! -f "$FILE" ]; then
        echo "ERROR: required file missing:"
        echo "  $FILE"
        echo
        echo "Run: python scripts/generate-traefik-cert.py"
        exit 1
    fi
done

##############################################
# PREPARE BUNDLE
##############################################

echo "========================================="
echo " Creating Offline Bundle"
echo "========================================="

if [ "$CLEAN_BUNDLE" = true ]; then
    rm -rf "$BUNDLE_DIR"
fi

mkdir -p "$BUNDLE_DIR"

##############################################
# COLLECT IMAGES
##############################################

echo
echo "Reading docker-compose..."

mapfile -t IMAGES < <(
docker compose -f "$COMPOSE_FILE" config \
| awk '/image:/ {print $2}' \
| sort -u
)

if [ "${#IMAGES[@]}" -eq 0 ]; then
    echo
    echo "ERROR: No images found."
    echo
    echo "Every service should have an 'image:' entry."
    exit 1
fi

echo
echo "Images to export:"
printf '  • %s\n' "${IMAGES[@]}"

##############################################
# VERIFY IMAGES
##############################################

echo
echo "Checking local images..."

for IMAGE in "${IMAGES[@]}"
do
    if docker image inspect "$IMAGE" >/dev/null 2>&1
    then
        echo "✔ $IMAGE"
    else
        echo
        echo "ERROR: Image not found:"
        echo "  $IMAGE"
        echo
        echo "Build or pull it first."
        exit 1
    fi
done

##############################################
# EXPORT
##############################################

ARCHIVE_FILE="${ARCHIVE_NAME}.tar"

echo
echo "Creating archive..."

docker save \
    "${IMAGES[@]}" \
    -o "${BUNDLE_DIR}/${ARCHIVE_FILE}"

##############################################
# COMPRESS
##############################################

if [ "$COMPRESS" = true ]; then

    echo
    echo "Compressing archive..."

    if command -v pigz >/dev/null 2>&1
    then
        pigz -f "${BUNDLE_DIR}/${ARCHIVE_FILE}"
    else
        gzip -f "${BUNDLE_DIR}/${ARCHIVE_FILE}"
    fi

    ARCHIVE_FILE="${ARCHIVE_FILE}.gz"

fi

##############################################
# COPY FILES
##############################################

echo
echo "Copying deployment files..."

for FILE in "${FILES_TO_COPY[@]}"
do
    if [ -e "$FILE" ]; then
        cp -R "$FILE" "$BUNDLE_DIR/"
        echo "✔ $FILE"
    fi
done

for DIR in "${DIRS_TO_COPY[@]}"
do
    if [ -d "$DIR" ]; then
        cp -R "$DIR" "$BUNDLE_DIR/"
        echo "✔ $DIR/"
    fi
done

##############################################
# SUMMARY
##############################################

echo
echo "Bundle Contents:"
ls -lh "$BUNDLE_DIR"

echo
du -sh "$BUNDLE_DIR"

##############################################
# PAUSE
##############################################

echo
echo "======================================================="
echo " Bundle has been created successfully."
echo
echo " 1) Disconnect Internet (if required)"
echo " 2) Connect VPN"
echo " 3) Verify SSH access"
echo
echo " Press ENTER to upload the bundle."
echo "======================================================="

read -r

# ##############################################
# # CHECK VPN
# ##############################################

# echo
# echo "Checking VPN..."

# if ! ping -c 1 "$REMOTE_HOST" >/dev/null 2>&1
# then
#     echo
#     echo "ERROR: Cannot reach $REMOTE_HOST"
#     echo "VPN may not be connected."
#     exit 1
# fi

##############################################
# CREATE REMOTE DIRECTORY
##############################################

echo
echo "Creating remote directory..."

ssh "${REMOTE_USER}@${REMOTE_HOST}" \
    "mkdir -p '${REMOTE_PATH}'"

##############################################
# TRANSFER
##############################################

echo
echo "Uploading bundle..."

scp -r \
    "${BUNDLE_DIR}/"* \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"

##############################################
# COMPLETE
##############################################

echo
echo "========================================="
echo " Upload completed successfully."
echo
echo " Remote Path:"
echo "   ${REMOTE_PATH}"
echo
echo " Next Steps:"
echo "   ssh ${REMOTE_USER}@${REMOTE_HOST}"
echo "   cd ${REMOTE_PATH}"
echo "   ./deploy-on-server.sh"
echo "========================================="
