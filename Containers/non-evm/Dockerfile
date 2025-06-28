FROM solanalabs/solana:v1.18.14

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git nodejs npm dos2unix jq \
    pkg-config build-essential libssl-dev libudev-dev llvm clang libclang-dev cmake unzip inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Set up Python virtual environment for AWS X-Ray SDK
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install aws-xray-sdk

# ====== FIX: Install Rust via rustup, and ensure Cargo is in the PATH ======
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# ====== Install Anchor CLI globally (for anchor build) ======
RUN npm install -g @coral-xyz/anchor-cli

# Install AVM (optional, AVM is not strictly required for anchor build)
RUN cargo install --git https://github.com/coral-xyz/anchor avm --locked --force || echo "AVM installation failed"

# Rust tools for linting and coverage
RUN rustup component add clippy && \
    cargo install cargo-audit cargo-expand cargo-tarpaulin || true

# Prepare directory structure
WORKDIR /app
RUN mkdir -p /app/src /app/tests /app/config /app/input /app/logs \
    /app/logs/coverage /app/logs/security /app/logs/analysis /app/logs/reports \
    /app/logs/xray /app/target /app/.cargo

# Copy your source, config, and test files
COPY config /app/config
COPY Cargo.toml /app/Cargo.toml
COPY src /app/src
COPY tests /app/tests

# Only copy entrypoint.sh (single script now)
COPY entrypoint.sh /app/entrypoint.sh
RUN dos2unix /app/entrypoint.sh && chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
