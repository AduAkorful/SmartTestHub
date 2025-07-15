# Use a recent, supported Rust image based on Debian Bookworm
FROM rust:1.72-bookworm

# Install system dependencies and tools
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
      npm && \
    rm -rf /var/lib/apt/lists/*

# Install Solana CLI (stable) using official installer script for reliability
ENV SOLANA_VERSION=1.18.12
RUN sh -c "$(curl -sSfL https://release.solana.com/v${SOLANA_VERSION}/install)"
ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"
RUN solana --version

# Install Anchor CLI (latest main branch)
RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked

# Install code coverage and audit tools for Rust
RUN cargo install cargo-tarpaulin cargo-audit

# Set workdir
WORKDIR /app

# Copy manifests (Cargo.toml always, Cargo.lock if it exists)
COPY Cargo.toml ./
# Use a shell trick to copy Cargo.lock only if it exists in build context
RUN test -f Cargo.lock || cargo generate-lockfile

# Pre-fetch dependencies for rapid test cycles
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    cargo fetch && \
    cargo build --release || true

# Copy project source and support files
COPY src ./src
COPY entrypoint.sh ./
COPY config ./config
COPY tests ./tests
COPY scripts ./scripts

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh || true

# Create log/report directories if needed
RUN mkdir -p /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

# Entrypoint (keep your advanced script orchestration)
ENTRYPOINT ["/app/entrypoint.sh"]
