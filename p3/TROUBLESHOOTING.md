# Part 3 Troubleshooting

## Reproduce the broken state

Run the node preparation before applying the workload:

```bash
bash troubleshoot/prepare.sh
kubectl apply -f troubleshoot/broken-app.yaml
kubectl get pods -n troubleshoot -o wide
kubectl get svc,endpoints,networkpolicy -n troubleshoot
```

The node labels and GPU taint must remain unchanged throughout the exercise.

## Issue 1: The web image cannot be pulled

Diagnosis commands:

```bash
kubectl get pods -n troubleshoot -l app=web
kubectl describe pod -n troubleshoot -l app=web
kubectl get events -n troubleshoot --sort-by=.lastTimestamp
```

Root cause: the Deployment used `nginx:1.25.99`, which is not a valid public image tag. The kubelet reports an image-pull failure and the web Pods never become ready.

Fix: use the available public image `nginx:1.25-alpine`.

## Issue 2: The web Deployment requests impossible memory

Diagnosis commands:

```bash
kubectl describe pod -n troubleshoot -l app=web
kubectl describe nodes
kubectl get events -n troubleshoot --sort-by=.lastTimestamp
```

Root cause: each web Pod requested `16Gi` of memory. That is excessive for the local four-worker test cluster and can leave the Pods Pending even after the image issue is fixed.

Fix: reduce the request to `16Mi` and set a reasonable `128Mi` memory limit.

## Issue 3: The web probes use the wrong port

Diagnosis commands:

```bash
kubectl describe pod -n troubleshoot -l app=web
kubectl logs -n troubleshoot -l app=web
kubectl exec -n troubleshoot deploy/web -- wget -qO- http://127.0.0.1:80/
```

Root cause: nginx listens on port 80, but both probes use port 8080. Kubernetes therefore marks otherwise-running containers as unhealthy.

Fix: point both liveness and readiness probes at port 80.

## Issue 4: The ConfigMap name is wrong

Diagnosis commands:

```bash
kubectl get configmap -n troubleshoot
kubectl describe pod -n troubleshoot -l app=web
kubectl get events -n troubleshoot --sort-by=.lastTimestamp
```

Root cause: the object is named `web-config`, while the Deployment refers to `web-conf`. The volume cannot be mounted.

Fix: reference `web-config` in the Deployment volume.

## Issue 5: The Service does not select the web Pods or their port

Diagnosis commands:

```bash
kubectl get pods -n troubleshoot --show-labels
kubectl get endpoints web-svc -n troubleshoot
kubectl describe svc web-svc -n troubleshoot
```

Root cause: the Service selects `app=webapp`, but the Pods are labeled `app=web`. It also targets port 8080 although nginx listens on port 80. The result is a Service with no usable endpoints.

Fix: select `app=web` and set `targetPort: 80`.

## Issue 6: The default-deny policy blocks the smoke test

Diagnosis commands:

```bash
kubectl get networkpolicy -n troubleshoot
kubectl apply -f troubleshoot/smoke-job.yaml
kubectl get pods -n troubleshoot -l app=smoke-client
kubectl logs -n troubleshoot job/smoke-test
```

Root cause: `default-deny` correctly denies all ingress and egress, but no least-privilege exceptions exist. The smoke client cannot resolve the Service DNS name or connect to the web Pods.

Fix: keep `default-deny` and add two policies:

- `allow-smoke-egress` permits DNS TCP/UDP 53 to `kube-system` and TCP 80 to Pods labeled `app=web`.
- `allow-smoke-to-web` permits TCP 80 ingress to web Pods only from Pods labeled `app=smoke-client`.

## Issue 7: The AI workload has the wrong node selector and no toleration

Diagnosis commands:

```bash
kubectl get nodes -L acme.io/node-type
kubectl describe node -l acme.io/node-type=gpu
kubectl get pod -n troubleshoot -l app=ai-inference -o wide
kubectl describe pod -n troubleshoot -l app=ai-inference
```

Root cause: node preparation labels the GPU node with `acme.io/node-type=gpu`, but the Deployment selects `node-type=gpu`. The GPU node is also tainted with `nvidia.com/gpu=true:NoSchedule`, and the Pod has no matching toleration.

Fix: select `acme.io/node-type: gpu` and add a toleration for the `nvidia.com/gpu` `NoSchedule` taint. The node labels and taint remain untouched.

## Verification

Apply the fixed manifests and run the provided verifier:

```bash
kubectl apply -f troubleshoot/fixed-app.yaml
./troubleshoot/verify.sh
```

The verifier checks the preserved default-deny policy, preserved node labels and taint, both Deployments, Service endpoints, and the in-cluster smoke test. The expected final output is `PASS`.
