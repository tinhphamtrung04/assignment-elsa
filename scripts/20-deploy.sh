#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment argocd-server -n argocd --timeout=120s

echo "==> Applying ArgoCD Application manifest..."
kubectl apply -f "$ROOT_DIR/p2/deploy/argocd-app.yaml"

echo "==> Triggering initial sync check..."
argocd app sync quote-api --namespace argocd || echo "ArgoCD CLI not found; waiting for Argo CD reconciliation."

echo "==> Waiting for Argo CD to create the application Deployment..."
for attempt in $(seq 1 90); do
  if kubectl get deployment/quote-api-on-demand >/dev/null 2>&1 && \
     kubectl get deployment/quote-api-spot >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "==> Waiting for quote-api deployment rollout..."
kubectl rollout status deployment/quote-api --timeout=180s

echo "==> Setup complete! Checking local curl capability..."
kubectl port-forward svc/quote-api 8080:80 &
PF_PID=$!
sleep 3
curl -s http://localhost:8080/api/quote
kill $PF_PID
