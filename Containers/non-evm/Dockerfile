FROM rust:bookworm

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
      wget && \
    rm -rf /var/lib/apt/lists/*

# Install sccache for Rust build caching (use pre-built binary for speed)
RUN curl -L "https://github.com/mozilla/sccache/releases/download/v0.7.7/sccache-v0.7.7-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz -C /tmp && \
    mv /tmp/sccache-v0.7.7-x86_64-unknown-linux-musl/sccache /usr/local/bin/ && \
    chmod +x /usr/local/bin/sccache

# Copy and extract Solana CLI (offline install)
COPY solana-release-x86_64-unknown-linux-gnu.tar.bz2 /tmp/
RUN mkdir -p /root/.local/share/solana/install && \
    tar -xjf /tmp/solana-release-x86_64-unknown-linux-gnu.tar.bz2 -C /root/.local/share/solana/install && \
    mv /root/.local/share/solana/install/solana-release* /root/.local/share/solana/install/active_release

ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

RUN solana --version

# Install ALL required Rust tools in one layer for better caching
RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked && \
    cargo install cargo-tarpaulin --locked && \
    cargo install cargo-audit --locked && \
    cargo install cargo-benchcmp --locked && \
    rustup component add clippy && \
    rustup component add rustfmt

# Install node dependencies for log aggregation
WORKDIR /app/scripts
RUN rm -rf node_modules package-lock.json
RUN npm cache clean --force
RUN npm install axios dotenv xml2js
WORKDIR /app

# Copy only the Cargo.toml for dependency layer caching
COPY Cargo.toml ./
# If Cargo.lock exists, use it; else, generate it on the fly
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    test -f Cargo.lock || cargo generate-lockfile && \
    cargo fetch || true

# Copy the rest of the source and scripts
COPY src ./src
COPY entrypoint.sh ./
COPY config ./config
COPY tests ./tests
COPY scripts ./scripts

RUN chmod +x /app/entrypoint.sh || true

# Create all necessary log directories
RUN mkdir -p /app/logs/coverage \
             /app/logs/reports \
             /app/logs/benchmarks \
             /app/logs/security \
             /app/logs/xray \
             /app/logs/analysis \
             /app/contracts

ENV CARGO_TARGET_DIR=/app/target
ENV RUSTC_WRAPPER=sccache
ENV SCCACHE_CACHE_SIZE=2G
ENV SCCACHE_DIR=/app/.cache/sccache
ENV CARGO_BUILD_JOBS=4
ENV RUSTFLAGS="-C target-cpu=native"

ENTRYPOINT ["/app/entrypoint.sh"]
