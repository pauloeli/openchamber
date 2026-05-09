#!/usr/bin/env bash
# Build (or rebuild) the openchamber Docker image from source and restart
# the container with the new version. Data is preserved via volume mounts.
#
# Usage:
#   ./scripts/build-image.sh             # build with layer cache
#   ./scripts/build-image.sh --no-cache  # force full rebuild (no cache)

set -euo pipefail

CONTAINER_NAME="openchamber"
COMPOSE_SERVICE="openchamber"

NO_CACHE=""
for arg in "$@"; do
  case "$arg" in
    --no-cache) NO_CACHE="--no-cache" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "==> Building image ..."
docker compose build ${NO_CACHE} "${COMPOSE_SERVICE}"

echo ""
echo "==> Cleaning dangling images ..."
docker image prune --force > /dev/null 2>&1 || true

echo ""
echo "==> Restarting container with new image ..."
docker compose up -d --force-recreate "${COMPOSE_SERVICE}"

echo ""
echo "==> Done."
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
