#!/usr/bin/env bash
set -e

echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment argocd-server -n argocd --timeout=120s

echo "==> Applying ArgoCD Application manifest..."
kubectl apply -f ../p2/deploy/argocd-app.yaml

echo "==> Triggering initial sync check..."
argocd app sync quote-api --namespace argocd || echo "ArgoCD CLI not found or managed via controller, skipping manual sync."

echo "==> Waiting for quote-api deployment rollout..."
kubectl rollout status deployment/quote-api --timeout=180s

echo "==> Setup complete! Checking local curl capability..."
kubectl port-forward svc/quote-api 8080:80 &
PF_PID=$!
sleep 3
curl -s http://localhost:8080/api/quote
kill $PF_PID
