# Start from a slim Rust image for speed and minimal size
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
      tzdata && \
    rm -rf /var/lib/apt/lists/*

# Install Solana CLI (stable)
ENV SOLANA_VERSION=1.18.12
RUN curl -sSfL https://release.solana.com/v${SOLANA_VERSION}/solana-release-x86_64-unknown-linux-gnu.tar.bz2 | \
    tar -xj -C /usr/local/bin --strip-components=2 solana-release/bin/solana

# Install Anchor CLI (latest)
RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked

# Set workdir
WORKDIR /app

# Cache dependencies for rapid test cycles
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    cargo fetch && \
    cargo build --release || true

# Copy source files
COPY . .

# Make entrypoint optional for your workflow
RUN chmod +x /app/entrypoint.sh || true

ENTRYPOINT ["/app/entrypoint.sh"]
