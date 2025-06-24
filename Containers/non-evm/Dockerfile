FROM solanalabs/solana:v1.18.14

# Install system dependencies you need
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git nodejs npm dos2unix jq \
    pkg-config build-essential libssl-dev libudev-dev llvm clang libclang-dev cmake unzip inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Set up Python virtual environment for AWS X-Ray SDK
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install aws-xray-sdk

# Install AVM and Anchor if needed
RUN cargo install --git https://github.com/coral-xyz/anchor avm --locked --force || echo "AVM installation failed"

# Rust tools for linting and coverage
RUN rustup component add clippy && \
    cargo install cargo-audit cargo-expand cargo-tarpaulin || true

# Prepare directory structure
WORKDIR /app
RUN mkdir -p /app/src /app/tests /app/config /app/input /app/logs \
    /app/logs/coverage /app/logs/security /app/logs/analysis /app/logs/reports \
    /app/logs/xray /app/target /app/.cargo

# Copy configuration files
COPY config /app/config
COPY Cargo.toml /app/Cargo.toml
COPY src /app/src
COPY tests /app/tests

# Copy entrypoint scripts
COPY entrypoint.sh /app/entrypoint.sh
COPY entrypoint-patch.sh /app/entrypoint-patch.sh
COPY entrypoint-wrapper.sh /app/entrypoint-wrapper.sh

RUN dos2unix /app/entrypoint.sh /app/entrypoint-patch.sh /app/entrypoint-wrapper.sh && \
    chmod +x /app/entrypoint.sh /app/entrypoint-patch.sh /app/entrypoint-wrapper.sh

# Entrypoint remains as wrapper
ENTRYPOINT ["/app/entrypoint-wrapper.sh"]
