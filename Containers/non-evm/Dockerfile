FROM rust:bookworm

# Install minimal required dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    pkg-config \
    libudev-dev \
    llvm \
    libclang-dev \
    protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

# Install sccache for Rust build caching
RUN cargo install sccache --locked

# Download and install pre-built Solana binaries
WORKDIR /root
RUN curl -Lo solana-release-x86_64-unknown-linux-gnu.tar.bz2 \
    "https://sourceforge.net/projects/solana.mirror/files/v1.18.25/solana-release-x86_64-unknown-linux-gnu.tar.bz2/download" && \
    tar jxf solana-release-x86_64-unknown-linux-gnu.tar.bz2 && \
    rm solana-release-x86_64-unknown-linux-gnu.tar.bz2

ENV PATH="/root/solana-release/bin:${PATH}"

# Generate keypair
RUN mkdir -p /root/.config/solana && \
    solana-keygen new --no-bip39-passphrase -o /root/.config/solana/id.json

# Set up Rust environment with updated targets
RUN rustup default stable && \
    rustup component add clippy rustfmt && \
    rustup target add wasm32-unknown-unknown && \
    rustup target add sbf-solana-solana

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
