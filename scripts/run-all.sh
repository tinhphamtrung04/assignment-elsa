#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Starting the toolbox container..."
docker compose up -d toolbox

echo "==> Waiting for kubectl, Helm, and k3d inside the toolbox..."
docker compose exec -T toolbox bash -lc '
  for attempt in $(seq 1 120); do
    if command -v kubectl >/dev/null 2>&1 &&
       command -v helm >/dev/null 2>&1 &&
       command -v k3d >/dev/null 2>&1; then
      exit 0
    fi
    sleep 2
  done
  echo "Timed out waiting for toolbox dependencies" >&2
  exit 1
'

echo "==> Running cluster setup, Argo CD deployment, Part 3 verification, and reclaim drill..."
docker compose exec -T toolbox bash -lc '
  set -euo pipefail
  cd /workspace
  bash scripts/10-setup.sh
  bash scripts/20-deploy.sh
  kubectl apply -f troubleshoot/broken-app.yaml
  kubectl apply -f troubleshoot/fixed-app.yaml
  bash troubleshoot/verify.sh
  bash scripts/25-reclaim-drill.sh
'

echo "==> Assignment CORE flow completed"
