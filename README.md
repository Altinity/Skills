# Skills

This repository contains skills used for ClickHouse DB performance and schema analysis and helper workflows.

## Core Skills
- `altinity-expert-clickhouse/`: Modular ClickHouse diagnostic skill set. Each module is a standalone skill under `altinity-expert-clickhouse/skills/` (e.g., memory, merges, replication).
- `automations/`: Batch and focus audit scripts that run full ClickHouse analysis and emit a single report.
- `releases/`: Built zip packages for distribution (one per skill).

## Use installed skills

### Claude Code / Claude Desktop / opencode
```
/skill-name prompt message
```

### Codex
```
$skill-name message
```

### Gemini Cli
gemini doesn't have dedicated syntax for skill usage, so you need use prompt like that

```
use skill skill-name message
```

## Install Skills

### Universal via npx (bunx if you use bun)
```
npx skills add --list Altinity/skills
npx skills add Altinity/skills
```

### Codex CLI

variants:
- use $skill-installer skill inside codex
- clone repo and copy needed skills into ~/.codex/skill directory.
- clone repo and ln (symlink) repo's skill directory into ~/.codex

### Claude CLI (Claude Code)

variants:
- claude skills add URL
- clone repo and copy needed skills into ~/.claude/skill directory.
- clone repo and ln (symlink) repo's skill directory into ~/.claude

### Gemini CLI

Install an agent skill from a git repository URL or a local path. 
```
gemini skills install <source> [--scope] [--path] 
```
 
or manually:

```sh
git clone https://github.com/Altinity/Skills.git
mkdir -p ~/.gemini/skills
cp /absolute/path/to/Skills/altinity-expert-clickhouse/skills/altinity-expert-clickhouse-memory ~/.gemini/skills/
# or
ln -s /absolute/path/to/Skills/altinity-expert-clickhouse/skills ~/.gemini/skills/
```


### Claude.ai (web)
Download the zip files from https://github.com/Altinity/skills/releases/ and upload them in Settings (or Admin Settings for org‑wide use) to Capabilities section. 


## Docker Image

A pre-built Docker image with Claude Code, Codex CLI, and all skills is available:

```bash
docker pull ghcr.io/altinity/skills:latest
```

The image includes:
- `claude` - Anthropic Claude Code CLI
- `codex` - OpenAI Codex CLI
- `clickhouse-client` - ClickHouse client
- `altinity-mcp` - Altinity MCP server

### Run locally with Docker

```bash
# Claude agent
docker run -it --rm \
  -v ~/.claude:/home/bun/.claude \
  ghcr.io/altinity/skills:latest \
  claude --dangerously-skip-permissions -p "/altinity-clickhouse-expert Analyze cluster health"

# Codex agent
docker run -it --rm \
  -v ~/.codex:/home/bun/.codex \
  ghcr.io/altinity/skills:latest \
  codex --dangerously-skip-permissions "\$altinity-clickhouse-expert Analyze cluster health"
```

## Kubernetes Helm Chart

A Helm chart is provided to run skills as Kubernetes Jobs in non-interactive (YOLO) mode.

### Install the chart

#### From OCI Registry (Recommended)

```bash
# Install with Claude agent (default)
helm install my-audit oci://ghcr.io/altinity/skills-helm-chart/skills-agent \
  --set skillName=altinity-clickhouse-expert \
  --set prompt="Analyze ClickHouse cluster health" \
  --set-file credentials.claudeCredentials=~/.claude/.credentials.json

# Install with Codex agent
helm install my-audit oci://ghcr.io/altinity/skills-helm-chart/skills-agent \
  --set agent=codex \
  --set skillName=altinity-expert-clickhouse-audit \
  --set prompt="Run full audit" \
  --set-file credentials.codexAuth=~/.codex/auth.json
```

#### From Local Repository

```bash
# Clone the repository
git clone https://github.com/Altinity/skills.git
cd skills

# Install with Claude agent (default)
helm install my-audit ./helm/skills-agent \
  --set skillName=altinity-clickhouse-expert \
  --set prompt="Analyze ClickHouse cluster health" \
  --set-file credentials.claudeCredentials=~/.claude/.credentials.json

# Install with Codex agent
helm install my-audit ./helm/skills-agent \
  --set agent=codex \
  --set skillName=altinity-expert-clickhouse-audit \
  --set prompt="Run full audit" \
  --set-file credentials.codexAuth=~/.codex/auth.json
```

### Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `agent` | Agent to use: `claude` or `codex` | `claude` |
| `skillName` | Skill name (without `/` or `$` prefix) | `altinity-clickhouse-expert` |
| `prompt` | Prompt to pass to the skill | `Analyze ClickHouse cluster health` |
| `image.repository` | Docker image repository | `ghcr.io/altinity/skills` |
| `image.tag` | Docker image tag | `latest` |
| `credentials.create` | Create credentials secret | `true` |
| `credentials.existingSecretName` | Use existing secret name | `""` |
| `credentials.claudeCredentials` | Claude `.credentials.json` content | (placeholder) |
| `credentials.codexAuth` | Codex `auth.json` content | (placeholder) |
| `job.ttlSecondsAfterFinished` | Auto-cleanup after completion | `3600` |
| `job.activeDeadlineSeconds` | Job timeout | `1800` |
| `extraEnv` | Additional environment variables | `[]` |

### Using existing secrets

If you prefer to manage credentials separately:

```bash
# Create secret manually
kubectl create secret generic agent-credentials \
  --from-file=claude-credentials.json=~/.claude/.credentials.json \
  --from-file=codex-auth.json=~/.codex/auth.json

# Install chart with existing secret
helm install my-audit ./helm/skills-agent \
  --set credentials.create=false \
  --set credentials.existingSecretName=agent-credentials \
  --set skillName=altinity-clickhouse-expert \
  --set prompt="Run diagnostics"
```

### Monitor job execution

```bash
# Check job status
kubectl get jobs -l app.kubernetes.io/instance=my-audit

# View logs
kubectl logs -l app.kubernetes.io/instance=my-audit -f

# Get pods
kubectl get pods -l app.kubernetes.io/instance=my-audit
```

## Experimental Skills
- `experimental/codex-summarize-pipeline/`: Chunk→reduce pipeline for summarizing large articles/files into `summaries/*.md`.
- `experimental/github-triage/`: Search and summarize relevant GitHub issues/PRs using `gh`.
- `experimental/sub-agent/`: Prototype sub-agent workflow (multi-agent attempt by exec of next codex/claude inside skill processing).

## Conventions
- Each skill lives in its own directory and includes a `SKILL.md`.
- Supporting content is stored next to `SKILL.md` (e.g., `modules/`, scripts, prompts).
