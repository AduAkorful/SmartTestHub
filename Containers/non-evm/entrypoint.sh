#!/bin/bash
set -e

chmod +x "$0" || true

LOG_FILE="/app/logs/test.log"
ERROR_LOG="/app/logs/error.log"
SECURITY_LOG="/app/logs/security/security-audit.log"
PERFORMANCE_LOG="/app/logs/analysis/performance.log"
XRAY_LOG="/app/logs/xray/xray.log"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$ERROR_LOG")"
mkdir -p "$(dirname "$SECURITY_LOG")"
mkdir -p "$(dirname "$PERFORMANCE_LOG")"
mkdir -p "$(dirname "$XRAY_LOG")"
mkdir -p /app/logs/coverage
mkdir -p /app/logs/reports
mkdir -p /app/logs/benchmarks

if [ -f "/app/.env" ]; then
    export $(cat /app/.env | grep -v '^#' | xargs)
    echo "✅ Environment variables loaded from .env"
fi

log_with_timestamp() {
    local message="$1"
    local log_type="${2:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    case $log_type in
        "error") echo "$timestamp ❌ $message" | tee -a "$LOG_FILE" "$ERROR_LOG" ;;
        "security") echo "$timestamp 🛡️ $message" | tee -a "$LOG_FILE" "$SECURITY_LOG" ;;
        "performance") echo "$timestamp ⚡ $message" | tee -a "$LOG_FILE" "$PERFORMANCE_LOG" ;;
        "xray") echo "$timestamp 📡 $message" | tee -a "$LOG_FILE" "$XRAY_LOG" ;;
        *) echo "$timestamp $message" | tee -a "$LOG_FILE" ;;
    esac
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Ensures /app/base-Cargo.lock exists, generating it from base-Cargo.toml if needed
ensure_base_cargo_lock() {
    if [ ! -f /app/base-Cargo.lock ]; then
        log_with_timestamp "🔄 base-Cargo.lock not found, generating from base-Cargo.toml..."
        tmpdir=$(mktemp -d)
        cp /app/base-Cargo.toml "$tmpdir/Cargo.toml"
        pushd "$tmpdir" > /dev/null
        cargo generate-lockfile || { log_with_timestamp "❌ Failed to generate Cargo.lock" "error"; popd > /dev/null; rm -rf "$tmpdir"; exit 1; }
        cp Cargo.lock /app/base-Cargo.lock
        popd > /dev/null
        rm -rf "$tmpdir"
        log_with_timestamp "✅ base-Cargo.lock generated."
    fi
}

# Detect contract type: returns "solana" for Solana/Anchor, "ink" for ink!, "unknown" otherwise
detect_contract_type() {
    if grep -q "ink_lang" /app/src/lib.rs || grep -q "#\[ink" /app/src/lib.rs; then
        echo "ink"
    elif grep -q "anchor_lang" /app/src/lib.rs || grep -q "solana_program" /app/src/lib.rs; then
        echo "solana"
    else
        echo "unknown"
    fi
}

generate_dynamic_cargo_toml() {
    # Always use pre-cached base for best cache hit
    cp /app/base-Cargo.toml /app/Cargo.toml
    cp /app/base-Cargo.lock /app/Cargo.lock
    # Optionally, add per-contract dependencies here if needed
}

main_pipeline() {
    contract_type=$(detect_contract_type)
    if [ "$contract_type" = "ink" ]; then
        log_with_timestamp "❌ ink! contracts are not supported in this pipeline." "error"
        exit 1
    elif [ "$contract_type" = "solana" ]; then
        log_with_timestamp "Detected Solana/Anchor contract."
        ensure_base_cargo_lock
        generate_dynamic_cargo_toml
    else
        log_with_timestamp "❌ Unknown contract type. Exiting." "error"
        exit 1
    fi

    log_with_timestamp "Running cargo build..."
    cargo build --release 2>&1 | tee -a "$LOG_FILE"

    log_with_timestamp "Running cargo test..."
    cargo test 2>&1 | tee -a "$LOG_FILE"

    log_with_timestamp "Running cargo tarpaulin for coverage..."
    cargo tarpaulin --out Html --out Json --out Xml --out Lcov --timeout 120 2>&1 | tee -a "$LOG_FILE"

    log_with_timestamp "Running cargo audit for security..."
    cargo audit 2>&1 | tee -a "$SECURITY_LOG"

    log_with_timestamp "Running cargo clippy for linting..."
    cargo clippy --all-targets --all-features -- -D warnings 2>&1 | tee -a "$SECURITY_LOG"
}

# === Duplicate prevention mechanism (atomic marker + lock) ===
MARKER_DIR="/app/.processed"
mkdir -p "$MARKER_DIR"

WATCH_FILE="/app/src/lib.rs"
MARKER_FILE="$MARKER_DIR/$(basename "$WATCH_FILE").processed"

if [ -f "$WATCH_FILE" ]; then
    (
        exec 9>"$MARKER_FILE.lock"
        if ! flock -n 9; then
            log_with_timestamp "⏭️ Lock exists for $WATCH_FILE, skipping (concurrent event)"
            exit 0
        fi

        if [ -f "$MARKER_FILE" ]; then
            LAST_PROCESSED=$(cat "$MARKER_FILE")
            # Extra safety check: ignore marker file if timestamp is not plausible
            if [[ "$LAST_PROCESSED" =~ ^[0-9]+$ ]] && [ "$LAST_PROCESSED" -gt 1700000000 ] && [ "$LAST_PROCESSED" -lt 4102444800 ]; then
                CURRENT_TIME=$(date +%s)
                if (( $CURRENT_TIME - $LAST_PROCESSED < 30 )); then
                    log_with_timestamp "⏭️ Skipping duplicate processing of $WATCH_FILE (processed ${LAST_PROCESSED}s ago)"
                    exit 0
                fi
            else
                log_with_timestamp "⚠️ Ignoring invalid or poisoned marker file for $WATCH_FILE (found: '$LAST_PROCESSED')" "warning"
            fi
        fi
        date +%s > "$MARKER_FILE"

        log_with_timestamp "🚀 Starting analysis pipeline for $WATCH_FILE"
        main_pipeline "$@"
        log_with_timestamp "🏁 Finished analysis pipeline for $WATCH_FILE"
    )
else
    log_with_timestamp "❌ No /app/src/lib.rs contract found. Exiting." "error"
    exit 1
fi
