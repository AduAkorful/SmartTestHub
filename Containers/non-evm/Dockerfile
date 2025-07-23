FROM rust:bookworm

RUN apt-get update && \
    apt-get install -y \
    build-essential \
    pkg-config \
    libudev-dev \
    llvm \
    libclang-dev \
    protobuf-compiler \
    curl \
    git \
    inotify-tools \
    nodejs \
    npm && \
    rm -rf /var/lib/apt/lists/*

RUN cargo install sccache --locked

WORKDIR /root

RUN curl -sSf https://release.anza.xyz/v1.16.15/install | sh && \
    export PATH="/root/.local/share/solana/install/active_release/bin:$PATH" && \
    mkdir -p /root/.config/solana && \
    solana-keygen new --no-bip39-passphrase --silent -o /root/.config/solana/id.json

ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

RUN rustup default stable && \
    rustup component add clippy rustfmt && \
    rustup target add wasm32-unknown-unknown

RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --tag v0.28.0 --locked && \
    cargo install cargo-audit --version 0.21.0 --locked

COPY ./scripts /app/scripts
WORKDIR /app/scripts
RUN npm install axios dotenv

RUN mkdir -p /app/input /app/logs /app/.cache/sccache /app/target

COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

ENV CARGO_TARGET_DIR=/app/target \
    RUSTC_WRAPPER=sccache \
    SCCACHE_CACHE_SIZE=4G \
    SCCACHE_DIR=/app/.cache/sccache \
    CARGO_BUILD_JOBS=4 \
    RUST_LOG=info \
    CARGO_TERM_COLOR=always \
    ANCHOR_WALLET=/root/.config/solana/id.json \
    SOLANA_VERSION=1.16.15

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
