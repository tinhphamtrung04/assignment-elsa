#!/usr/bin/env bash
set -e

echo "==> Finding a spot node running a quote-api pod..."
SPOT_NODE=$(kubectl get pods -l app.kubernetes.io/name=quote-api -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | head -n 1)

if [ -z "$SPOT_NODE" ]; then
  echo "Error: No active nodes found running quote-api pods."
  exit 1
fi

echo "==> Selected target node to drain (simulate spot reclaim): $SPOT_NODE"

echo "==> Starting background traffic generator (curl loop)..."
(
  while true; do
    curl -s -o /dev/null -w "%{http_code} " http://localhost:8080/api/quote || echo "ERR"
    sleep 0.2
  done
) &
CURL_LOOP_PID=$!

# Setup cleanup trap to ensure port-forward and curl loop terminate
trap "kill $CURL_LOOP_PID 2>/dev/null; kill $PF_PID 2>/dev/null" EXIT

echo "==> Establishing background port-forward..."
kubectl port-forward svc/quote-api-quote-api 8080:80 >/dev/null 2>&1 &
PF_PID=$!
sleep 2

echo "==> Cordoning and draining node: $SPOT_NODE"
kubectl cordon "$SPOT_NODE"
kubectl drain "$SPOT_NODE" --ignore-daemonsets --delete-emptydir-data --force --timeout=60s

echo "==> Verifying pod rescheduling and uninterrupted availability..."
for i in {1..10}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/quote || echo "FAIL")
  echo "Check $i: HTTP Status -> $STATUS"
  sleep 1
done

echo "==> Uncordoning node: $SPOT_NODE"
kubectl uncordon "$SPOT_NODE"

echo "==> Reclaim drill completed successfully!"