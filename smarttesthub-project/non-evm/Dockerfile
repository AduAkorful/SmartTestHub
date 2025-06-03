FROM rust:latest

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash git curl libssl-dev pkg-config protobuf-compiler llvm clang libclang-dev cmake dos2unix ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV CARGO_TERM_COLOR=always

RUN cargo install wasm-bindgen-cli --version 0.2.88
RUN cargo install anchor-cli@0.29.0
RUN cargo install --locked cargo-tarpaulin cargo-audit cargo-deny cargo-outdated

# Copy entrypoint script first and fix line endings
COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh

WORKDIR /app
COPY . .

ENTRYPOINT ["/entrypoint.sh"]
