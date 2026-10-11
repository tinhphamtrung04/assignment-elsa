# AI Usage Disclosure

## Tools used

I used OpenAI Codex in the desktop workspace as an engineering assistant. Codex was used for:

- Reviewing the Argo CD Application and Helm chart.
- Comparing the application’s runtime port with the Kubernetes Deployment, probes, and Service.
- Reviewing and correcting the reclaim-drill workflow.
- Creating the Part 3 fixed manifests and troubleshooting narrative.
- Creating the project README, architecture diagrams, and script reference.
- Creating the `scripts/run-all.sh` entrypoint and validating shell, Helm, Docker Compose, and YAML changes.

The final decisions, file changes, and verification were reviewed against the assignment requirements and tested with local commands where the environment allowed it.

## Representative prompts

1. **Argo CD diagnosis**

   > review the argocd-app.yaml. the container is working local but argocd canot run it

   This led to inspecting the Dockerfile, application source, Helm templates, rendered manifests, and deployment scripts. The port mismatch was identified: the application listens on 8080 while the Deployment declared 8000.

2. **Reclaim-drill correction**

   > the purpose of this file is scripts/25-reclaim-drill.sh must drain one spot node, show the service still answers (curl loop), show pods rescheduling, then uncordon.

   This clarified that the test had to exercise the Kubernetes Service rather than merely keep a direct Pod port-forward alive.

3. **Assignment-wide automation**

   > base on the requirement, create run-all.sh to do the assignment from scratch

   This resulted in a repository-root entrypoint that starts the toolbox and runs cluster setup, Argo CD deployment, Part 3 verification, and the reclaim drill.

## Example of incorrect or suboptimal AI output

The first reclaim-drill implementation was suboptimal. After the original script used `kubectl port-forward svc/quote-api`, the selected backend Pod was evicted and the output showed:

```text
error forwarding port ... network namespace ... is closed
000 ERR
```

The initial AI correction was to port-forward directly to a surviving quote-api Pod. That avoided the tunnel closing when the drained Pod was evicted, but it no longer tested the Kubernetes Service as required by the assignment.

I corrected the approach by restating the exact acceptance criterion:

> `scripts/25-reclaim-drill.sh` must drain one spot node, show the service still answers (curl loop), show pods rescheduling, then uncordon.

That made the distinction explicit: keeping a direct Pod connection alive was not enough; the test had to send traffic through the Service during the reclaim. The next attempted fix restarted the Service port-forward when its backend disappeared, but that still produced a port-forward artifact and was not a clean Service-level test.

I then asked for a temporary script to test the Service from inside the cluster. The final correction was to create an in-cluster temporary curl Pod on a non-target node and send requests to:

```text
http://quote-api.default.svc.cluster.local/api/quote
```

The curl Pod records every response, the script drains a spot node, waits for quote-api Pods to reschedule, and the drill passes only when the recorded responses are HTTP 200. After I ran it, the output showed the evicted Pod rescheduled to another node and a stream of HTTP 200 responses. The working implementation was then consolidated into `scripts/25-reclaim-drill.sh`.

## Verification and ownership

Examples of verification performed after AI-assisted changes include:

```bash
bash -n scripts/*.sh troubleshoot/*.sh
helm template quote-api p2/charts/quote-api
docker compose config
git diff --check
```

The reclaim workflow was also run against the local cluster. It drained a spot node, rescheduled the quote-api Pod, recorded only HTTP 200 Service responses from inside the cluster, and uncordoned the node.
