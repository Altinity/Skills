FROM ghcr.io/altinity/altinity-mcp:latest AS mcp

FROM docker.io/oven/bun:debian
RUN bash -xec "apt-get update && apt-get install --no-install-recommends -y wget gpg curl ca-certificates unzip git git-lfs && \
    wget -qO- 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor --verbose -o /usr/share/keyrings/clickhouse-keyring.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg arch=$(dpkg --print-architecture)] https://packages.clickhouse.com/deb stable main' > /etc/apt/sources.list.d/clickhouse.list && \
    apt-get update -y && \
    update-ca-certificates && \
    apt-get install --no-install-recommends -y clickhouse-client && \
    curl 'https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip' -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip && \
    rm -rf /var/lib/apt/lists/* && rm -rf /var/cache/apt/*"

ENV BUN_INSTALL=/opt/bun
ENV PATH="/opt/bun/bin:${PATH}"

RUN bun install -g @openai/codex@latest \
  && bun install -g @anthropic-ai/claude-code@latest \
  && bunx skills add --global --agent claude-code --yes Altinity/Skills \
  && bunx skills add --global --agent codex --yes Altinity/Skills \
  && codex --version \
  && claude --version \
  && chown -R bun:bun /opt/bun /home/bun

ENV HOME=/home/bun
USER bun

COPY --from=mcp --chown=bun:bun /bin/altinity-mcp /bin/altinity-mcp

RUN mkdir -p /home/bun/.codex \
  && cat <<'EOF' > /home/bun/.codex/config.toml
model = "gpt-5.2-codex"
model_reasoning_effort = "medium"
web_search = "live"

[mcp_servers.clickhouse]
command = "/bin/altinity-mcp"
args = ["--config","/etc/altinity-mcp.yaml"]
EOF
