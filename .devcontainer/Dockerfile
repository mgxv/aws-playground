FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Install AWS CLI v2 if not already present
RUN set -e \
    && if ! which aws > /dev/null 2>&1; then \
        apt-get update \
        && apt-get install -y --no-install-recommends curl unzip \
        && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
        && unzip awscliv2.zip \
        && ./aws/install \
        && rm -rf awscliv2.zip aws/ \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*; \
    fi
