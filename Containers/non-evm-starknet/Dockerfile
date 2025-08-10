FROM python:3.11-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        inotify-tools \
        nodejs \
        npm \
        git \
        curl \
        ca-certificates \
        build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

COPY src ./src
COPY tests ./tests
COPY config ./config
# Ensure all helper scripts (including test generator) are available in the container
COPY scripts/ ./scripts/
COPY entrypoint.sh ./

RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /app/input /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

# Install Scarb (Cairo 1 toolchain) and StarkNet Foundry (snforge/sncast)
RUN curl -fsSL https://docs.swmansion.com/scarb/install.sh | bash && \
    echo 'export PATH="/root/.local/bin:$PATH"' >> /etc/profile.d/scarb.sh && \
    /bin/bash -lc 'which scarb && scarb --version' || true

# Install Starknet Foundry via snfoundryup (best-effort; continue if unavailable)
RUN curl -fsSL https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | bash || true
ENV PATH="/root/.starknet-foundry/bin:/root/.local/bin:${PATH}"

ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/entrypoint.sh"]
