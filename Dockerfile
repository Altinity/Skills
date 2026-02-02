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

USER bun
ENV HOME=/home/bun
RUN bun install -g @openai/codex@latest
RUN bun install -g @anthropic-ai/claude-code@latest
RUN bunx skills add --global --agent claude-code --yes  Altinity/Skills
RUN bunx skills add --global --agent codex --yes Altinity/Skills


COPY --from=mcp /bin/altinity-mcp /bin/altinity-mcp
