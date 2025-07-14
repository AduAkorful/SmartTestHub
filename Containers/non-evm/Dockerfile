FROM solanalabs/solana:v1.18.14

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git curl dos2unix jq \
    pkg-config build-essential libssl-dev libudev-dev llvm clang libclang-dev cmake unzip inotify-tools \
    nodejs npm yarn \
    && rm -rf /var/lib/apt/lists/*

# Install Rust 1.85.0 (overrides Solana image's Rust)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.85.0
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Solana CLI 2.1.15 (reinstall over existing if needed)
RUN sh -c "$(curl -sSfL https://release.solana.com/v2.1.15/install)"
ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

# Install Anchor CLI 0.31.1
RUN cargo install --git https://github.com/coral-xyz/anchor --tag v0.31.1 anchor-cli --locked

# ---- OPTIMIZED RUST DEPENDENCY CACHING ----
WORKDIR /app

# Copy only Cargo.toml first for Docker cache efficiency
COPY Cargo.toml ./

# Generate Cargo.lock if it doesn't exist (library projects)
RUN test -f Cargo.lock || cargo generate-lockfile

# Copy Cargo.lock (guaranteed to exist now)
COPY Cargo.lock ./

# Pre-build dependencies to cache them, using dummy src/lib.rs
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    cargo fetch && \
    cargo build --release || true

# Now copy the rest of the app, including source, scripts, etc.
COPY . /app

# Install latest cargo-deny and other dev tools, pin cargo-expand to a Rust 1.85.0-compatible version
RUN cargo install cargo-deny && \
    cargo install cargo-audit && \
    cargo install cargo-expand --version 1.0.109 && \
    cargo install cargo-tarpaulin

# Optional: Set up Python virtual environment for AWS X-Ray SDK
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install aws-xray-sdk

# Make entrypoint script executable if present
RUN chmod +x /app/entrypoint.sh || true

# Update entrypoint to only launch main script (no node upload server)
RUN echo '#!/bin/bash\n\
exec /app/entrypoint.sh "$@"' > /app/docker-entrypoint.sh && chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
