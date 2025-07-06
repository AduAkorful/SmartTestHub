FROM ghcr.io/foundry-rs/foundry:latest

USER root

RUN apt-get update && apt-get install -y \
    bash \
    git \
    curl \
    build-essential \
    libffi-dev \
    libssl-dev \
    python3 \
    python3-pip \
    python3-venv \
    dos2unix \
    inotify-tools \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && node --version \
    && npm --version

RUN python3 -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install slither-analyzer && \
    echo 'source /opt/venv/bin/activate' >> /root/.bashrc

ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /app

RUN apt-get update && apt-get install -y \
    python3 make g++ \
    && npm install -g node-gyp

COPY package.json package-lock.json* ./
RUN npm install --no-optional || npm install --no-optional --force

RUN npm install -g @openzeppelin/hardhat-upgrades \
    hardhat-contract-sizer hardhat-docgen hardhat-storage-layout \
    @ethereum/security-analysis solidity-coverage hardhat-gas-reporter eth-gas-reporter \
    || echo "Some packages may not be available"

COPY . .

RUN dos2unix ./entrypoint.sh && chmod +x ./entrypoint.sh

RUN echo '#!/bin/bash\n\
source /opt/venv/bin/activate\n\
chmod +x /app/entrypoint.sh\n\
exec /app/entrypoint.sh "$@"' > /docker-entrypoint.sh \
    && chmod +x /docker-entrypoint.sh

RUN mkdir -p /app/input /app/logs /app/contracts /app/test \
    /app/logs/slither /app/logs/coverage /app/logs/gas /app/logs/foundry \
    /app/logs/reports /app/cache /app/artifacts

RUN forge init --force || true

RUN chmod -R 755 /app/logs /app/input /app/contracts /app/test

ENV NODE_ENV=development
ENV REPORT_GAS=true

ENTRYPOINT ["/docker-entrypoint.sh"]
