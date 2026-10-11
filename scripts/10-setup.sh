#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="assignment"

echo "==> Checking if k3d cluster '$CLUSTER_NAME' already exists..."
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Cluster '$CLUSTER_NAME' already exists. Skipping creation (Idempotent)."
else
  echo "==> Creating k3d cluster with 1 server and 4 worker nodes..."
  k3d cluster create "$CLUSTER_NAME" \
    --agents 4 \
    --api-port 6443 \
    --wait
fi

echo "==> Running troubleshoot/prepare.sh to label and taint nodes..."
if [ -f "$SCRIPT_DIR/../troubleshoot/prepare.sh" ]; then
  bash "$SCRIPT_DIR/../troubleshoot/prepare.sh"
else
  echo "==> Fallback: Applying standard production labels/taints manually..."
  NODES=$(kubectl get nodes --no-headers -l '!node-role.kubernetes.io/control-plane' -o name)
  
  COUNT=0
  for NODE in $NODES; do
    if [ $COUNT -eq 0 ]; then
      echo "Configuring $NODE as on-demand..."
      kubectl label node "$NODE" node.kubernetes.io/lifecycle=on-demand --overwrite
    elif [ $COUNT -eq 1 ]; then
      echo "Configuring $NODE as GPU node..."
      kubectl label node "$NODE" accelerator=nvidia-gpu --overwrite
    else
      echo "Configuring $NODE as spot node..."
      kubectl label node "$NODE" node.kubernetes.io/lifecycle=spot --overwrite
    fi
    COUNT=$((COUNT + 1))
  done
fi

echo "==> Cluster bootstrap complete!"
kubectl get nodes -o wide
