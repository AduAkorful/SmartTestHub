FROM solanalabs/solana:v1.18.14

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git curl dos2unix jq \
    pkg-config build-essential libssl-dev libudev-dev llvm clang libclang-dev cmake unzip inotify-tools \
    nodejs npm yarn \
    && rm -rf /var/lib/apt/lists/*

# Install Rust 1.86.0 (overrides Solana image's Rust for compatibility with modern cargo tools)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.86.0
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Solana CLI 2.1.15 (reinstall over existing if needed)
RUN sh -c "$(curl -sSfL https://release.solana.com/v2.1.15/install)"
ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

# Install Anchor CLI 0.31.1
RUN cargo install --git https://github.com/coral-xyz/anchor --tag v0.31.1 anchor-cli --locked

# Install latest cargo-deny and other dev tools (with --locked for reproducibility)
RUN cargo install --locked cargo-deny && \
    cargo install --locked cargo-audit && \
    cargo install --locked cargo-expand && \
    cargo install --locked cargo-tarpaulin

# Optional: Set up Python virtual environment for AWS X-Ray SDK
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install aws-xray-sdk

WORKDIR /app
COPY . /app
RUN rm -f /app/Cargo.lock

# Make entrypoint script executable if present
RUN chmod +x /app/entrypoint.sh || true
RUN echo '#!/bin/bash\n\
exec /app/entrypoint.sh "$@"' > /app/docker-entrypoint.sh && chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
