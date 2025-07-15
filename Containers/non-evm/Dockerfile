FROM rust:1.72-buster

# Install system dependencies
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

# Install tools for code coverage and security (optional but recommended)
RUN cargo install cargo-tarpaulin cargo-audit

# Set workdir
WORKDIR /app

# Copy manifests (Cargo.toml and Cargo.lock if exists)
COPY Cargo.toml ./
COPY Cargo.lock .  # removes error if not present, optional

# Pre-fetch dependencies for rapid test cycles
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    cargo fetch && \
    cargo build --release || true

# Copy source and support files
COPY src ./src
COPY entrypoint.sh ./
COPY config ./config
COPY tests ./tests
COPY scripts ./scripts

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh || true

# Expose log/report directories if needed
RUN mkdir -p /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

# Entrypoint (or change to CMD for more flexibility)
ENTRYPOINT ["/app/entrypoint.sh"]
