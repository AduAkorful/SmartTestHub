FROM rust:bookworm

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

RUN cargo install sccache

# Solana CLI (offline install)
COPY solana-release-x86_64-unknown-linux-gnu.tar.bz2 /tmp/
RUN mkdir -p /root/.local/share/solana/install && \
    tar -xjf /tmp/solana-release-x86_64-unknown-linux-gnu.tar.bz2 -C /root/.local/share/solana/install && \
    mv /root/.local/share/solana/install/solana-release* /root/.local/share/solana/install/active_release
ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"
RUN solana --version

RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked && \
    cargo install cargo-tarpaulin --locked && \
    cargo install cargo-audit --locked && \
    rustup component add clippy

WORKDIR /app

# Install Node.js dependencies for scripts
COPY scripts/package.json /app/scripts/
RUN cd /app/scripts && npm install

# Pre-cache all Rust dependencies including dev-deps
COPY Cargo.toml ./
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs
RUN cargo generate-lockfile
RUN SCCACHE_CACHE_SIZE=2G SCCACHE_DIR=/app/.cache/sccache RUSTC_WRAPPER=sccache \
    cargo fetch && \
    SCCACHE_CACHE_SIZE=2G SCCACHE_DIR=/app/.cache/sccache RUSTC_WRAPPER=sccache \
    cargo build --release --all-features --all-targets || true && \
    SCCACHE_CACHE_SIZE=2G SCCACHE_DIR=/app/.cache/sccache RUSTC_WRAPPER=sccache \
    cargo test --no-run --all-features --all-targets || true

COPY src ./src
COPY tests ./tests
COPY config ./config
COPY entrypoint.sh ./
COPY scripts ./scripts

RUN chmod +x /app/entrypoint.sh || true
RUN mkdir -p /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

ENV CARGO_TARGET_DIR=/app/target
ENV RUSTC_WRAPPER=sccache
ENV SCCACHE_CACHE_SIZE=2G
ENV SCCACHE_DIR=/app/.cache/sccache
ENV CARGO_BUILD_JOBS=4
ENV RUSTFLAGS="-C target-cpu=native"

ENTRYPOINT ["/app/entrypoint.sh"]
