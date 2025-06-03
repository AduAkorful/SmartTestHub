#!/bin/bash
set -e

echo "Starting Non-EVM tools..."

# Run Anchor tests
echo "Running Anchor tests..."
anchor test || true

# Run Tarpaulin code coverage
echo "Running Tarpaulin for code coverage..."
cargo tarpaulin --out Html || true

# Run X-ray fuzzing
echo "Running X-ray fuzzing..."
cargo xray fuzz || true

# Static analysis (optional)
echo "Running static analysis..."
cargo audit || true
cargo deny check || true
cargo outdated || true
cargo clippy --all-targets --all-features -- -D warnings || true

echo "Non-EVM tools execution completed."

exec "$@"
