# Ops Answers

## 1. EKS 1.33 → 1.35 with no planned downtime

I would upgrade one minor version at a time: 1.33 → 1.34 → 1.35. Before each step I would run EKS Upgrade Insights, check deprecated APIs, back up critical manifests/data, confirm spare capacity, review PodDisruptionBudgets, and rehearse on a staging cluster. EKS documents the high-level sequence as control plane, data plane, then add-ons and clients; I would also ensure the existing nodes are on the latest patch before each control-plane transition. [AWS upgrade guidance](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)

For each minor version: upgrade the control plane and wait for `ACTIVE`; update compatible managed add-ons—`vpc-cni`, `kube-proxy`, and CoreDNS—preserving reviewed configuration; update EBS CSI and EFS CSI, including their IAM roles; then create/surge a new managed node group at the target version. Cordon and drain old nodes respecting PDBs, verify DaemonSets, DNS, networking, mounts, ingress, and application SLOs, and remove old nodes only after the new pool is healthy. Roll back by stopping the next step and shifting traffic back to the old pool; do not delete the old pool until validation completes. Add-on versions should be selected with `describe-addon-versions` for the target Kubernetes version. [AWS add-on guidance](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)

Top three risks: (1) deprecated API or webhook incompatibility, mitigated by Upgrade Insights, inventory, and canary admission; (2) insufficient capacity/PDBs or singleton workloads blocking drains, mitigated by surge capacity and tested disruption budgets; (3) CNI/CSI/IAM/configuration drift causing networking or storage failures, mitigated by preserving configuration, staged add-on updates, and storage read/write tests.

## 2. Stop false-positive node alert storms

Use a multi-signal alert with a delay: page only when a node is `NotReady` or `Unknown` for 10 minutes **and** node-exporter/kubelet telemetry is absent or workloads cannot schedule. Group alerts by cluster and node, and inhibit dependent Pod alerts while the node alert is active. Use a warning ticket for a short interruption and a page only when the condition persists or affects workload availability.

Integrate EC2 Auto Scaling/Spot interruption events through EventBridge. When a reclaim notice, cordon, drain, or planned node-group update is known, silence that node’s alert for the maintenance window and route spot-node interruptions to a non-paging channel. Do not suppress alerts for on-demand nodes, control-plane symptoms, quorum loss, or a node that remains unreachable after the expected reclaim window. Alert separately on deployment availability, Service error rate, and unschedulable Pods so a real outage still pages even when a node alert is suppressed.

## 3. Diagnose Cloudflare HTML caching and LCP

First separate real-user mobile LCP from synthetic results and split LCP into TTFB, resource load delay, resource duration, and render delay. Reproduce the same URL with:

```bash
curl -sSI https://site.example/ 
curl -sSI https://site.example/ 
```

Compare `cf-cache-status`, `age`, `cache-control`, `etag`, `vary`, `set-cookie`, `location`, and `server-timing`; a repeated anonymous request should become `HIT` with a growing `Age`. Check redirects and query strings separately. In Cloudflare, inspect Cache Rules order, bypass expressions for cookies/authorization, Workers, origin cache-control, and whether the HTML rule is actually eligible to cache. Confirm the origin is not sending `private`, `no-store`, or a session cookie that forces bypass. Purge only the affected hostname/path after correcting the rule, then verify MISS → HIT from multiple regions.

If HTML is cached but LCP remains 5s, inspect the LCP element and waterfall: preload the hero image, serve responsive modern formats, remove render-blocking CSS/JS, compress HTML, and use early hints where useful. Do not cache personalized HTML; bypass `/api/*` and vary only on required content.

## 4. Secrets on multiple EKS clusters

Kubernetes Secrets are simple and integrate with native mounts/env vars, but they still require etcd encryption with KMS, strict RBAC, rotation automation, and careful prevention of secret values entering Git or logs. They also create per-cluster copies and drift.

AWS Secrets Manager with IAM-scoped access through EKS Pod Identity/IRSA and the Secrets Store CSI Driver (ASCP) centralizes ownership, audit, rotation, and recovery. The trade-offs are AWS coupling, IAM/CSI operational complexity, and the need to handle rotation semantics for applications that read secrets only at startup. [AWS ASCP guidance](https://docs.aws.amazon.com/eks/latest/userguide/manage-secrets.html)

For a startup running several production clusters, I would choose Secrets Manager plus ASCP/CSI, with one IAM role per workload and least-privilege secret ARNs per environment. Enable rotation and KMS encryption, use separate paths/accounts for environments, and test rotation without restart where the application supports it.

## Bonus: tracing the quote endpoint

Add OpenTelemetry instrumentation around `/api/quote`, propagate W3C trace context through ingress, export OTLP to a collector, and sample heavily in production while retaining errors and slow traces. Record `trace_id` in structured logs and attach attributes such as route, status, and duration; never record quotes, credentials, or arbitrary request headers. Dashboard p95 latency and error rate by trace/span data, then correlate slow spans with CPU throttling and HPA events.
