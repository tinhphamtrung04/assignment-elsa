# GitLab CI to GitHub Actions Migration

## What changed

The workflow is `.github/workflows/ci.yml`.

## Migrated CI/CD flow

![CI/CD migration flow](docs/cicd-flow.png)

- The GitLab `sonar_check` job was migrated to SonarCloud. The workflow waits for the SonarCloud Quality Gate with `-Dsonar.qualitygate.wait=true`, so a red gate fails the job and prevents image publication. The old `allow_failure: true` behavior was intentionally removed.
- The legacy Node.js unit-test job was removed because this service is Python and has no Node package or npm test suite. The Python source is analyzed by SonarCloud and the container build validates the runtime packaging.
- The Docker build now uses the actual Part 1 context (`p1`) and Dockerfile (`p1/dockerfile`) instead of the repository root.
- Images are pushed to GHCR, not GitLab’s registry.
- The image tag is the short Git commit SHA. No mutable `latest` tag is published.
- The deploy job was not copied. Deployment remains GitOps-managed by the Argo CD Application, which reconciles the Helm chart from the repository.
- The workflow uses GitHub’s built-in `GITHUB_TOKEN` with job-scoped `packages: write` permission instead of long-lived registry credentials.

## GitLab variable and secret migration

For a real migration, I would inventory every GitLab CI variable, classify it as configuration or secret, and move only secrets into GitHub Actions encrypted secrets or environment-level secrets:

| Legacy value | GitHub Actions destination | Notes |
|---|---|---|
| `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD` | `GITHUB_TOKEN` plus `packages: write` | Prefer the short-lived repository token for GHCR. |
| `SONAR_HOST_URL` / `SONAR_TOKEN` | `SONAR_TOKEN` repository secret and the fixed SonarCloud URL | The project key and organization are configured in the workflow. |
| `KUBECONFIG_CONTENT` | Deployment environment secret or, preferably, removed | Argo CD owns deployment; long-lived kubeconfigs should not be stored in CI. |
| AWS credentials | GitHub OIDC role assumption | Do not copy static access keys into repository secrets. |
| Image name and region | Workflow `env` or repository variables | Non-sensitive configuration does not need secret storage. |

Production deployments would use GitHub OIDC with short-lived cloud credentials and protected environments for any operation that changes infrastructure. Pull requests run the quality gate only; image publication occurs after the gate passes on the protected default branch.

## SonarCloud setup and gate policy

Before the first workflow run, create or import the public project in SonarCloud with organization `tinhphamtrung04` and project key `tinhphamtrung04_assignment-elsa`. Add a repository secret named `SONAR_TOKEN` containing a SonarCloud analysis token.

Configure the project Quality Gate so any new bug, vulnerability, security hotspot, or code smell makes the gate fail. The workflow waits for that gate before the build job can run; it is not an informational scan.

SonarCloud documents that `sonar.qualitygate.wait=true` makes the scanner poll the computed gate and fail the analysis step when the gate is red: <https://docs.sonarsource.com/sonarqube-server/2025.2/devops-platform-integration/github-integration/adding-analysis-to-github-actions-workflow>.

The image build can be reproduced locally with:

```bash
docker build -f p1/dockerfile -t ghcr.io/tinhphamtrung04/assignment1:$(git rev-parse --short HEAD) p1
```
