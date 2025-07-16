FROM rust:1.72-bookworm

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

# Copy and extract Solana CLI (offline install)
COPY solana-release-x86_64-unknown-linux-gnu.tar.bz2 /tmp/
RUN mkdir -p /root/.local/share/solana/install && \
    tar -xjf /tmp/solana-release-x86_64-unknown-linux-gnu.tar.bz2 -C /root/.local/share/solana/install && \
    mv /root/.local/share/solana/install/solana-release* /root/.local/share/solana/install/active_release

ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

RUN solana --version

RUN cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked

RUN cargo install cargo-tarpaulin cargo-audit

WORKDIR /app

COPY Cargo.toml ./
RUN test -f Cargo.lock || cargo generate-lockfile

RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    cargo fetch && \
    cargo build --release || true

COPY src ./src
COPY entrypoint.sh ./
COPY config ./config
COPY tests ./tests
COPY scripts ./scripts

RUN chmod +x /app/entrypoint.sh || true

RUN mkdir -p /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

ENTRYPOINT ["/app/entrypoint.sh"]
