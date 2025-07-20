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
      npm && \
    rm -rf /var/lib/apt/lists/*

# Install sccache for Rust build caching
RUN cargo install sccache

# Copy and extract Solana CLI (offline install)
COPY solana-release-x86_64-unknown-linux-gnu.tar.bz2 /tmp/
RUN mkdir -p /root/.local/share/solana/install && \
    tar -xjf /tmp/solana-release-x86_64-unknown-linux-gnu.tar.bz2 -C /root/.local/share/solana/install && \
    mv /root/.local/share/solana/install/solana-release* /root/.local/share/solana/install/active_release

ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

RUN solana --version

# Install anchor, tarpaulin, audit, and clippy (as rustup component) in one layer for cache
RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked && \
    cargo install cargo-tarpaulin --locked && \
    cargo install cargo-audit --locked && \
    rustup component add clippy

# Install node dependencies for log aggregation (no package.json required)
WORKDIR /app/scripts
RUN rm -rf node_modules package-lock.json
RUN npm cache clean --force
RUN npm install axios dotenv xml2js
WORKDIR /app

# Prepare and build the Rust AST cleaner binary
WORKDIR /app/scripts
COPY scripts/clean_rust.rs /app/scripts/
RUN mkdir -p cleaner/src && \
    mv clean_rust.rs cleaner/src/main.rs && \
    echo "[package]\nname = \"cleaner\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\nsyn = { version = \"2\", features = [\"visit-mut\"] }\nprettyplease = \"0.2\"\nproc_macro2 = \"1\"\n" > cleaner/Cargo.toml && \
    cd cleaner && cargo build --release && \
    cp target/release/cleaner /usr/local/bin/clean_rust

WORKDIR /app

# Copy only the Cargo.toml for dependency layer caching
COPY Cargo.toml ./
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    test -f Cargo.lock || cargo generate-lockfile && \
    cargo fetch && \
    SCCACHE_CACHE_SIZE=2G SCCACHE_DIR=/app/.cache/sccache RUSTC_WRAPPER=sccache cargo build --release || true

# Copy the rest of the source and scripts
COPY src ./src
COPY entrypoint.sh ./
COPY config ./config
COPY tests ./tests
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
