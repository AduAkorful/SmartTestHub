FROM ghcr.io/coral-xyz/anchor:0.31.1

WORKDIR /app

# Cache dependencies for fast rebuilds
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    cargo fetch && \
    cargo build --release || true

COPY . .

RUN chmod +x /app/entrypoint.sh || true

ENTRYPOINT ["/app/entrypoint.sh"]
