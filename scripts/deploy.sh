#!/usr/bin/env bash
set -euo pipefail

NEW_IMAGE="$1"
APP_PORT="${2:-3000}"
MEMORY_LIMIT="${3:-256m}"
CPU_LIMIT="${4:-0.5}"

BLUE_CONTAINER="kanban-blue"
GREEN_CONTAINER="kanban-green"
BLUE_PORT=3001
GREEN_PORT=3002
NGINX_UPSTREAM_CONF="/etc/nginx/conf.d/kanban-upstream.conf"

echo "=========================================="
echo "Starting Zero-Downtime Deployment"
echo "Target Image: ${NEW_IMAGE}"
echo "=========================================="

# Determine currently active container (Blue or Green)
if docker ps --format '{{.Names}}' | grep -q "^${BLUE_CONTAINER}$"; then
    ACTIVE_CONTAINER="${BLUE_CONTAINER}"
    IDLE_CONTAINER="${GREEN_CONTAINER}"
    IDLE_PORT="${GREEN_PORT}"
else
    ACTIVE_CONTAINER="${GREEN_CONTAINER}"
    IDLE_CONTAINER="${BLUE_CONTAINER}"
    IDLE_PORT="${BLUE_PORT}"
fi

echo "Active Container : ${ACTIVE_CONTAINER}"
echo "Deploying to Idle: ${IDLE_CONTAINER} on internal port ${IDLE_PORT}"

# Clean up any leftover stopped idle container
docker rm -f "${IDLE_CONTAINER}" 2>/dev/null || true

# Pull latest verified tag
docker pull "${NEW_IMAGE}"

# Start new container alongside old container with strict resource limits
docker run -d \
    --name "${IDLE_CONTAINER}" \
    --restart unless-stopped \
    --memory="${MEMORY_LIMIT}" \
    --cpus="${CPU_LIMIT}" \
    --read-only \
    --tmpfs /var/cache/nginx:uid=1001,gid=1001 \
    --tmpfs /var/run:uid=1001,gid=1001 \
    -p "127.0.0.1:${IDLE_PORT}:3000" \
    "${NEW_IMAGE}"

echo "Waiting for ${IDLE_CONTAINER} health check to pass..."
MAX_RETRIES=12
SLEEP_SECONDS=5
HEALTHY=false

for i in $(seq 1 ${MAX_RETRIES}); do
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${IDLE_CONTAINER}" 2>/dev/null || echo "starting")
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${IDLE_PORT}/health" || echo "000")

    echo "Attempt ${i}/${MAX_RETRIES} -> Docker Health: ${HEALTH_STATUS} | HTTP Status: ${HTTP_CODE}"

    if [ "${HEALTH_STATUS}" = "healthy" ] && [ "${HTTP_CODE}" = "200" ]; then
        HEALTHY=true
        break
    fi
    sleep "${SLEEP_SECONDS}"
done

if [ "${HEALTHY}" != "true" ]; then
    echo "CRITICAL: New container ${IDLE_CONTAINER} failed health validation! Initiating ROLLBACK..."
    docker logs "${IDLE_CONTAINER}" || true
    docker rm -f "${IDLE_CONTAINER}" || true
    echo "ROLLBACK COMPLETE: ${ACTIVE_CONTAINER} continues serving production traffic undisturbed."
    exit 1
fi

# Switch Host Nginx Reverse Proxy Upstream to new healthy container
echo "Health check passed! Switching traffic to ${IDLE_CONTAINER} (127.0.0.1:${IDLE_PORT})..."
sudo tee "${NGINX_UPSTREAM_CONF}" > /dev/null <<EOF
server {
    listen ${APP_PORT};
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${IDLE_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

sudo nginx -t && sudo nginx -s reload

# Gracefully stop and remove old container only after traffic switch
if docker ps --format '{{.Names}}' | grep -q "^${ACTIVE_CONTAINER}$"; then
    echo "Stopping and removing previous container: ${ACTIVE_CONTAINER}"
    docker stop "${ACTIVE_CONTAINER}"
    docker rm "${ACTIVE_CONTAINER}"
fi

echo "=========================================="
echo "DEPLOYMENT SUCCESSFUL! Live on port ${APP_PORT}"
echo "=========================================="
docker ps --filter "name=${IDLE_CONTAINER}"
