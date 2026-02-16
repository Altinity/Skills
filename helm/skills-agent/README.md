# altinity-expert Helm Chart

Run Claude or Codex with Skills in Kubernetes as a one-shot Job (or debug Pod).

- Chart name: `altinity-expert`
- Chart path: `helm/skills-agent`
- OCI reference: `oci://ghcr.io/altinity/skills-helm-chart/altinity-expert`

## Prerequisites

- Kubernetes 1.24+
- Helm 3.12+
- Pull access to `ghcr.io/altinity/expert` image
- Agent auth file(s): Claude (`.credentials.json`) and/or Codex (`auth.json`)

## Install

### OCI

```bash
# Pin a version in production with --version <chart-version>
helm install my-audit oci://ghcr.io/altinity/skills-helm-chart/altinity-expert \
  --set skillName=altinity-expert-clickhouse-overview \
  --set prompt="Analyze ClickHouse cluster health" \
  --set-file credentials.claudeCredentials=~/.claude/.credentials.json
```

### Local

```bash
helm install my-audit ./helm/skills-agent \
  --set agent=codex \
  --set model=gpt-5.2-codex \
  --set skillName=altinity-expert-clickhouse-overview \
  --set prompt="Analyze ClickHouse cluster health and summarize top risks" \
  --set-file credentials.codexAuth=~/.codex/auth.json
```

## Validate Before Apply

```bash
helm lint ./helm/skills-agent
helm template my-audit ./helm/skills-agent
```

## Common Config

| Key | Description | Default |
|---|---|---|
| `debugMode` | Use debug Pod instead of Job | `false` |
| `agent` | Agent CLI (`claude` or `codex`) | `claude` |
| `model` | Codex model (used only when `agent=codex`) | `""` |
| `skillName` | Skill name (no `/` or `$`) | `altinity-clickhouse-expert` |
| `prompt` | Prompt text passed to skill | `Analyze ClickHouse cluster health` |
| `image.repository` | Agent image repository | `ghcr.io/altinity/expert` |
| `image.tag` | Agent image tag | `latest` |
| `imagePullSecrets` | Pull secrets list | `[]` |
| `job.restartPolicy` | Pod restart policy | `Never` |
| `job.backoffLimit` | Job retry count | `0` |
| `job.ttlSecondsAfterFinished` | Cleanup TTL seconds | `3600` |
| `job.activeDeadlineSeconds` | Max runtime seconds | `1800` |
| `resources` | CPU/memory requests + limits | see `values.yaml` |
| `extraEnv` | Additional environment variables | `[]` |
| `nodeSelector` | Node selector | `{}` |
| `tolerations` | Pod tolerations | `[]` |
| `affinity` | Pod affinity | `{}` |

## ClickHouse Connection Values

| Key | Description | Default |
|---|---|---|
| `clickhouse.host` | ClickHouse host | `localhost` |
| `clickhouse.port` | ClickHouse port | `9440` |
| `clickhouse.user` | ClickHouse user | `default` |
| `clickhouse.password` | ClickHouse password | `""` |
| `clickhouse.tls.enabled` | Enable TLS in generated configs | `true` |
| `clickhouse.tls.ca` | PEM CA content | `""` |
| `clickhouse.tls.cert` | PEM client cert content | `""` |
| `clickhouse.tls.key` | PEM client key content | `""` |

The chart generates and mounts:
- `/etc/clickhouse-client/config.xml`
- `/etc/altinity-mcp/config.yaml`
- optional TLS files under `/etc/clickhouse-client/` and `/etc/altinity-mcp/`

## Credentials Secret Modes

### Mode A: Chart creates secret (`credentials.create=true`)

This is the default. Provide auth file content with `--set-file`.

```bash
helm install my-audit ./helm/skills-agent \
  --set skillName=altinity-expert-clickhouse-overview \
  --set prompt="Analyze ClickHouse cluster health" \
  --set-file credentials.claudeCredentials=~/.claude/.credentials.json
```

### Mode B: Existing secret (`credentials.create=false`)

Your secret must include these keys:
- `codex-auth.json`
- `claude-credentials.json`
- `clickhouse-client-config.xml`
- `altinity-mcp-config.yaml`
- optional TLS keys (if TLS files are referenced): `clickhouse-ca.crt`, `clickhouse-client.crt`, `clickhouse-client.key`

```bash
helm install my-audit ./helm/skills-agent \
  --set credentials.create=false \
  --set credentials.existingSecretName=agent-credentials \
  --set skillName=altinity-expert-clickhouse-overview \
  --set prompt="Run diagnostics"
```

## Debug Mode

```bash
helm install my-debug oci://ghcr.io/altinity/skills-helm-chart/altinity-expert \
  --set debugMode=true \
  --set skillName=altinity-expert-clickhouse-overview \
  --set prompt="Analyze ClickHouse cluster health" \
  --set-file credentials.claudeCredentials=~/.claude/.credentials.json
```

```bash
kubectl exec -it <release-name>-altinity-expert-debug -- /bin/sh
kubectl logs <release-name>-altinity-expert-debug
```

## Store Results in S3

### IRSA (recommended on EKS)

IRSA requires service account creation in this chart:

```bash
helm install my-audit oci://ghcr.io/altinity/skills-helm-chart/altinity-expert \
  --set skillName=altinity-expert-clickhouse-overview \
  --set prompt="Analyze ClickHouse cluster health" \
  --set-file credentials.claudeCredentials=~/.claude/.credentials.json \
  --set storeResults.enabled=true \
  --set storeResults.s3Bucket=my-results-bucket \
  --set storeResults.s3Prefix=agent-results \
  --set storeResults.iamRoleArn=arn:aws:iam::123456789012:role/my-eks-s3-role \
  --set serviceAccount.create=true
```

### Static AWS credentials

```bash
helm install my-audit oci://ghcr.io/altinity/skills-helm-chart/altinity-expert \
  --set skillName=altinity-expert-clickhouse-overview \
  --set prompt="Analyze ClickHouse cluster health" \
  --set-file credentials.claudeCredentials=~/.claude/.credentials.json \
  --set storeResults.enabled=true \
  --set storeResults.s3Bucket=my-results-bucket \
  --set storeResults.awsAccessKeyId=AKIAIOSFODNN7EXAMPLE \
  --set storeResults.awsSecretAccessKey=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

Behavior:
- Logs are written in-container to `/workspace/${TIMESTAMP}/agent-execution.log`.
- If agent exit code is `0`, the work directory uploads to `s3://${S3_BUCKET}/${S3_PREFIX}/${TIMESTAMP}/`.
- If agent exit code is non-zero, upload is skipped.

## Service Account

| Key | Description | Default |
|---|---|---|
| `serviceAccount.create` | Create a ServiceAccount | `false` |
| `serviceAccount.name` | Name override | `""` |
| `serviceAccount.namespace` | Namespace for created SA | `""` |
| `serviceAccount.annotations` | Additional SA annotations | `{}` |

## Troubleshooting

1. Wrong OCI path
Use `oci://ghcr.io/altinity/skills-helm-chart/altinity-expert`.

2. IRSA not taking effect
Set both `storeResults.iamRoleArn` and `serviceAccount.create=true`.

3. Skill not found
Use an existing skill directory name under `altinity-expert-clickhouse/skills`.

4. Secret mount errors with existing secret
Verify required keys are present (`codex-auth.json`, `claude-credentials.json`, `clickhouse-client-config.xml`, `altinity-mcp-config.yaml`).

5. Validate rendered manifests
Run `helm template my-audit ./helm/skills-agent` before install.
