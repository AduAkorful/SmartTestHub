FROM rust:bookworm

# Install minimal required dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    pkg-config \
    libudev-dev \
    llvm \
    libclang-dev \
    protobuf-compiler \
    curl \
    git && \
    rm -rf /var/lib/apt/lists/*

# Install sccache for Rust build caching
RUN cargo install sccache --locked

WORKDIR /root

# Install Solana using the Agave installer with a specific version
RUN curl -sSf https://release.anza.xyz/v2.2.14/install | sh && \
    . /root/.profile && \
    solana-install init

ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

# Generate keypair
RUN mkdir -p /root/.config/solana && \
    solana-keygen new --no-bip39-passphrase -o /root/.config/solana/id.json

# Set up Rust environment with correct toolchain
RUN rustup default stable && \
    rustup component add clippy rustfmt && \
    rustup target add wasm32-unknown-unknown

# Install Anchor and other tools
RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --tag v0.30.1 --locked && \
    cargo install cargo-audit --version 0.21.0 --locked

# Verify installations
RUN solana --version && \
    cargo --version && \
    anchor --version

ENV CARGO_TARGET_DIR=/app/target \
    RUSTC_WRAPPER=sccache \
    SCCACHE_CACHE_SIZE=4G \
    SCCACHE_DIR=/app/.cache/sccache \
    CARGO_BUILD_JOBS=4 \
    RUST_LOG=info \
    CARGO_TERM_COLOR=always \
    ANCHOR_WALLET=/root/.config/solana/id.json \
    SOLANA_VERSION=1.18.25

WORKDIR /app
ENTRYPOINT ["/bin/bash"]
