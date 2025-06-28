FROM solanalabs/solana:v1.18.14

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git curl dos2unix jq \
    nodejs npm pkg-config build-essential libssl-dev libudev-dev llvm clang libclang-dev cmake unzip inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Set up Python virtual environment for AWS X-Ray SDK
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:/root/.cargo/bin:$PATH"

RUN pip install aws-xray-sdk

# Install Rust (rustup) and add to PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Add cargo and rustup to PATH for all future RUN and ENTRYPOINT
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Anchor CLI via cargo (NOT npm, to avoid GLIBC mismatch)
RUN cargo install --git https://github.com/coral-xyz/anchor --tag v0.29.0 anchor-cli --locked

# Rust tools for linting and coverage
RUN rustup component add clippy && \
    cargo install cargo-audit cargo-expand cargo-tarpaulin

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
