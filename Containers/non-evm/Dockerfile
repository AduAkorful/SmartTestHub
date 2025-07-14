FROM projectserum/build:latest

WORKDIR /app

# Step 1: Cache dependencies
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo "pub fn dummy() {}" > src/lib.rs && \
    cargo fetch && \
    cargo build --release || true

# Step 2: Copy actual sources, configs, scripts
COPY . .

# Step 3: Make entrypoint executable
RUN chmod +x /app/entrypoint.sh || true

# Step 4: Run your entrypoint as before
ENTRYPOINT ["/app/entrypoint.sh"]
