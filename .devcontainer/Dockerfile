FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Install AWS CLI v2
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws/ \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install latest stable Go
RUN curl -fsSL "https://go.dev/dl/$(curl -fsSL https://go.dev/VERSION?m=text | head -1).linux-amd64.tar.gz" -o go.tar.gz \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# Install Node.js 24 directly
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code (runs as root during build, so no permission issues)
RUN npm install -g @anthropic-ai/claude-code
