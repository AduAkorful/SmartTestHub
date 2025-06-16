FROM ghcr.io/foundry-rs/foundry:latest

# Set the user to root explicitly
USER root

# Install system dependencies (without nodejs from apt)
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

# Install Node.js v18 (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && node --version \
    && npm --version

# Create a Python virtual environment and install tools
RUN python3 -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install slither-analyzer solc-select && \
    solc-select install 0.8.18 && \
    solc-select use 0.8.18 && \
    echo 'source /opt/venv/bin/activate' >> /root/.bashrc

# Add solc to PATH
ENV PATH="/root/.solc-select/artifacts/solc-0.8.18:/opt/venv/bin:${PATH}"

# Set working directory
WORKDIR /app

# Install node-gyp dependencies for native modules
RUN apt-get update && apt-get install -y \
    python3 make g++ \
    && npm install -g node-gyp

# Copy package.json and install Node.js dependencies
COPY package.json package-lock.json* ./

# Install specific versions of required packages
RUN npm install --save-dev \
    hardhat@^2.19.0 \
    @nomicfoundation/hardhat-toolbox@^3.0.0 \
    @nomicfoundation/hardhat-network-helpers@^1.0.0 \
    hardhat-gas-reporter@^1.0.9 \
    hardhat-contract-sizer@^2.10.0 \
    @openzeppelin/contracts@^5.0.0 \
    solidity-coverage@^0.8.5 \
    prettier@^3.1.0 \
    prettier-plugin-solidity@^1.2.0

# Install additional security and analysis tools
RUN npm install --save-dev \
    @openzeppelin/hardhat-upgrades \
    hardhat-storage-layout \
    @ethereum/security-analysis

# Copy configuration files
COPY config/hardhat.config.js ./hardhat.config.js
COPY config/slither.config.json ./slither.config.json
COPY config/foundry.toml ./foundry.toml

# Create required directories
RUN mkdir -p /app/input /app/logs /app/contracts /app/test \
    /app/logs/slither /app/logs/coverage /app/logs/gas /app/logs/foundry \
    /app/logs/reports /app/cache /app/artifacts

# Initialize Foundry project structure
RUN forge init --force || true

# Set proper permissions
RUN chmod -R 755 /app/logs /app/input /app/contracts /app/test

# Add environment variable loading
ENV NODE_ENV=development
ENV REPORT_GAS=true
ENV SOLC_VERSION=0.8.18

# Copy all application files
COPY . .

# Fix script permissions and line endings
RUN dos2unix ./entrypoint.sh && chmod +x ./entrypoint.sh

# Use the entrypoint script
ENTRYPOINT ["./entrypoint.sh"]
