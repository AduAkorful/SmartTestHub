# Base image with fixed Rust version for compatibility
FROM rust:1.79.0-bookworm

# Install system dependencies and keep this as a separate layer for caching
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      pkg-config \
      build-essential \
      libssl-dev \
      libudev-dev \
      libclang-dev \
      cmake \
      curl \
      git \
      ca-certificates \
      tzdata \
      inotify-tools \
      nodejs \
      npm \
      jq \
      unzip && \
    rm -rf /var/lib/apt/lists/*

# Install sccache for Rust build caching
RUN cargo install sccache --locked

# Copy and extract Solana CLI (offline install)
COPY solana-release-x86_64-unknown-linux-gnu.tar.bz2 /tmp/
RUN mkdir -p /root/.local/share/solana/install && \
    tar -xjf /tmp/solana-release-x86_64-unknown-linux-gnu.tar.bz2 -C /root/.local/share/solana/install && \
    mv /root/.local/share/solana/install/solana-release* /root/.local/share/solana/install/active_release && \
    rm -f /tmp/solana-release-x86_64-unknown-linux-gnu.tar.bz2

ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

# Verify Solana installation
RUN solana --version

# Set up Rust environment
RUN rustup default 1.79.0 && \
    rustup component add clippy rustfmt && \
    rustup target add bpf-unknown-unknown

# Install enhanced toolchain with proper versions and security tools
RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --tag v0.30.1 --locked && \
    cargo install cargo-tarpaulin --version 0.31.2 --locked && \
    cargo install cargo-audit --version 0.21.0 --locked && \
    cargo install cargo-benchcmp --locked && \
    cargo install cargo-nextest --locked

# Set up Node.js dependencies
WORKDIR /app/scripts
RUN rm -rf node_modules package-lock.json && \
    npm cache clean --force && \
    npm install axios@1.7.7 dotenv@16.4.5 xml2js@0.6.2 markdown-table@3.0.3 chalk@5.3.0

WORKDIR /app

# Copy configuration files first for better caching
COPY config ./config
COPY scripts ./scripts

# Copy only the Cargo.toml for dependency layer caching
COPY Cargo.toml ./
# Generate Cargo.lock if it doesn't exist
RUN mkdir -p src && \
    echo "pub fn dummy() {}" > src/lib.rs && \
    test -f Cargo.lock || cargo generate-lockfile && \
    cargo fetch && \
    SCCACHE_CACHE_SIZE=4G SCCACHE_DIR=/app/.cache/sccache RUSTC_WRAPPER=sccache cargo build --release || true

# Copy the rest of the source
COPY src ./src
COPY entrypoint.sh ./
COPY tests ./tests

RUN chmod +x /app/entrypoint.sh

# Create comprehensive directory structure
RUN mkdir -p \
    /app/logs/coverage \
    /app/logs/reports \
    /app/logs/benchmarks \
    /app/logs/security \
    /app/logs/performance \
    /app/logs/xray \
    /app/contracts \
    /app/input \
    /app/.processed \
    /app/.cache/sccache

# Enhanced environment variables
ENV CARGO_TARGET_DIR=/app/target \
    RUSTC_WRAPPER=sccache \
    SCCACHE_CACHE_SIZE=4G \
    SCCACHE_DIR=/app/.cache/sccache \
    CARGO_BUILD_JOBS=4 \
    RUSTFLAGS="-C target-cpu=native -C link-arg=-z -C link-arg=noexecstack" \
    RUST_LOG=info \
    CARGO_TERM_COLOR=always \
    CARGO_NET_RETRY=10 \
    CARGO_HTTP_TIMEOUT=30 \
    CARGO_HTTP_LOW_SPEED_LIMIT=10

# Use the entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]
