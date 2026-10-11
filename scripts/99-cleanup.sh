#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="assignment"
TOOLBOX_CONTAINER="k3d-toolbox"

cd "$ROOT_DIR"

echo "==> Removing k3d cluster: $CLUSTER_NAME"

# k3d is installed inside the toolbox by docker-compose.yml, so delete the
# exact cluster through the toolbox before taking the toolbox down.
if ! docker ps --format '{{.Names}}' | grep -Fxq "$TOOLBOX_CONTAINER" \
  && docker ps -a --format '{{.Names}}' | grep -Fxq "$TOOLBOX_CONTAINER"; then
  echo "==> Starting stopped toolbox temporarily to delete the cluster"
  docker start "$TOOLBOX_CONTAINER" >/dev/null
fi

if docker ps --format '{{.Names}}' | grep -Fxq "$TOOLBOX_CONTAINER"; then
  docker exec "$TOOLBOX_CONTAINER" bash -lc \
    "command -v k3d >/dev/null 2>&1 && k3d cluster delete '$CLUSTER_NAME' || true"
else
  echo "==> Toolbox is not running; cluster deletion command skipped"
fi

echo "==> Stopping and removing the Compose toolbox and project resources"
docker compose down --volumes --remove-orphans

# Remove the exact toolbox container if it was left behind by an interrupted
# Compose shutdown. This does not touch other containers.
if docker ps -a --format '{{.Names}}' | grep -Fxq "$TOOLBOX_CONTAINER"; then
  docker rm -f "$TOOLBOX_CONTAINER"
fi

echo "==> Local project cleanup completed"
echo "    Removed: k3d cluster '$CLUSTER_NAME', toolbox '$TOOLBOX_CONTAINER', Compose resources"
echo "    Preserved: Docker images, host-installed tools, and unrelated clusters"
