#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="default"
SELECTOR="app.kubernetes.io/name=quote-api"
CURL_POD="reclaim-service-check"
CURL_LOG="/tmp/${CURL_POD}.log"
TARGET_NODE=""
SURVIVOR_NODE=""
LOG_PID=""

cleanup() {
  [ -z "$LOG_PID" ] || kill "$LOG_PID" 2>/dev/null || true
  kubectl delete pod "$CURL_POD" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  if [ -n "$TARGET_NODE" ]; then
    kubectl uncordon "$TARGET_NODE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> Finding a quote-api pod on a spot node..."
while read -r POD NODE PHASE; do
  if [ "$PHASE" = "Running" ] && [ "$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.acme\.io/capacity}')" = "spot" ]; then
    TARGET_NODE="$NODE"
    break
  fi
done < <(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{" "}{.status.phase}{"\n"}{end}')

if [ -z "$TARGET_NODE" ]; then
  echo "ERROR: no running quote-api pod found on a spot node" >&2
  exit 1
fi

echo "==> Finding a surviving worker node..."
while read -r POD NODE PHASE; do
  if [ "$PHASE" = "Running" ] && [ "$NODE" != "$TARGET_NODE" ]; then
    SURVIVOR_NODE="$NODE"
    break
  fi
done < <(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{" "}{.status.phase}{"\n"}{end}')

if [ -z "$SURVIVOR_NODE" ]; then
  echo "ERROR: no running quote-api pod exists outside $TARGET_NODE" >&2
  exit 1
fi

echo "==> Starting in-cluster curl loop on $SURVIVOR_NODE"
kubectl delete pod "$CURL_POD" -n "$NAMESPACE" --ignore-not-found >/dev/null
kubectl run "$CURL_POD" -n "$NAMESPACE" \
  --image=curlimages/curl:8.7.1 \
  --restart=Never \
  --overrides="{\"spec\":{\"nodeName\":\"$SURVIVOR_NODE\"}}" \
  --command -- sh -c '
    end=$(( $(date +%s) + 120 ))
    while [ "$(date +%s)" -lt "$end" ]; do
      status=$(curl -s -o /dev/null -w "%{http_code}" \
        http://quote-api.default.svc.cluster.local/api/quote || true)
      echo "$status"
      [ "$status" = "200" ] || exit 1
      sleep 0.2
    done
  ' >/dev/null

if ! kubectl wait --for=jsonpath='{.status.phase}'=Running \
  pod/"$CURL_POD" -n "$NAMESPACE" --timeout=120s; then
  echo "ERROR: curl pod did not reach Running state. Diagnostics:" >&2
  kubectl get pod "$CURL_POD" -n "$NAMESPACE" -o wide >&2 || true
  kubectl describe pod "$CURL_POD" -n "$NAMESPACE" >&2 || true
  exit 1
fi
kubectl logs -f pod/"$CURL_POD" -n "$NAMESPACE" >"$CURL_LOG" 2>&1 &
LOG_PID=$!

echo "==> Draining spot node: $TARGET_NODE"
kubectl cordon "$TARGET_NODE"
kubectl drain "$TARGET_NODE" --ignore-daemonsets --delete-emptydir-data --force --timeout=120s

echo "==> Waiting for quote-api pods to reschedule..."
kubectl wait --for=condition=Ready pod -n "$NAMESPACE" -l "$SELECTOR" --timeout=120s
kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" -o wide

sleep 3
kill "$LOG_PID" 2>/dev/null || true
LOG_PID=""

echo "==> Checking Service responses from inside the cluster..."
cat "$CURL_LOG"
if awk '$0 != "200" { failed=1 } END { exit failed }' "$CURL_LOG"; then
  echo "PASS: quote-api Service returned only HTTP 200 responses during the reclaim drill"
else
  echo "FAIL: quote-api Service returned a non-200 response" >&2
  exit 1
fi

echo "==> Uncordoning node: $TARGET_NODE"
kubectl uncordon "$TARGET_NODE"
TARGET_NODE=""
echo "==> Service availability drill completed successfully"
