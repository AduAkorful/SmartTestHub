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

# Install Solana CLI (stable)
ENV SOLANA_VERSION=1.18.12
RUN curl -sSfL https://release.solana.com/v${SOLANA_VERSION}/solana-release-x86_64-unknown-linux-gnu.tar.bz2 | \
    tar -xj -C /usr/local/bin --strip-components=2 solana-release/bin/solana && \
    solana --version

# Install Anchor CLI (latest main branch)
RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked

# Install code coverage and audit tools for Rust
RUN cargo install cargo-tarpaulin cargo-audit

# Set workdir
WORKDIR /app

# Copy manifests (Cargo.toml always, Cargo.lock if it exists)
COPY Cargo.toml ./
# Copy Cargo.lock if it exists, but don't fail if missing
RUN if [ -f Cargo.lock ]; then cp Cargo.lock Cargo.lock; fi

# Pre-fetch dependencies for rapid test cycles.
# Generate a dummy lockfile if not present (for libraries)
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    if [ ! -f Cargo.lock ]; then cargo generate-lockfile; fi && \
    cargo fetch && \
    cargo build --release || true

# Copy source and project files
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
