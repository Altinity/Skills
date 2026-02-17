## Altinity Skills Release: {{TAG}}

### Artifacts
- Skill zip assets (one zip per skill):
  - https://github.com/Altinity/Skills/releases/tag/{{TAG}}

### Container Image (GHCR)
- Image name: `ghcr.io/altinity/expert`
- Package page:
  - https://github.com/orgs/Altinity/packages/container/package/expert
- Pull example:
  - `docker pull ghcr.io/altinity/expert:latest`

### Helm Chart (OCI in GHCR)
- Chart reference:
  - `oci://ghcr.io/altinity/skills-helm-chart/altinity-expert`
- Package page:
  - https://github.com/orgs/Altinity/packages/container/package/skills-helm-chart%2Faltinity-expert
- Pull/install examples:
  - `helm pull oci://ghcr.io/altinity/skills-helm-chart/altinity-expert --version <chart-version>`
  - `helm install my-audit oci://ghcr.io/altinity/skills-helm-chart/altinity-expert --version <chart-version>`

### Documentation
- Repository README:
  - https://github.com/Altinity/Skills/blob/main/README.md
- Helm chart README:
  - https://github.com/Altinity/Skills/blob/main/helm/skills-agent/README.md

### CI Workflows
- Skill packages workflow:
  - https://github.com/Altinity/Skills/actions/workflows/skills-zips.yaml
- Docker image workflow:
  - https://github.com/Altinity/Skills/actions/workflows/docker.yaml
- Helm chart workflow:
  - https://github.com/Altinity/Skills/actions/workflows/helm.yaml

### Notes
- Skills are distributed as individual zip files attached to this release.
- Docker image and Helm chart are distributed via GHCR (not as GitHub release binaries).
