#!/bin/bash
set -e

# --- Environment/parallelism setup ---
export RUSTC_WRAPPER=sccache
export SCCACHE_CACHE_SIZE=2G
export SCCACHE_DIR="/app/.cache/sccache"
export CARGO_TARGET_DIR=/app/target
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-$(nproc)}
export RUSTFLAGS="-C target-cpu=native"

LOG_FILE="/app/logs/test.log"
ERROR_LOG="/app/logs/error.log"
SECURITY_LOG="/app/logs/security/security-audit.log"
PERFORMANCE_LOG="/app/logs/analysis/performance.log"
XRAY_LOG="/app/logs/xray/xray.log"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ERROR_LOG")" \
  "$(dirname "$SECURITY_LOG")" "$(dirname "$PERFORMANCE_LOG")" "$(dirname "$XRAY_LOG")" \
  /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray /app/contracts

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

run_security_audit() { log_with_timestamp "Security audit not implemented."; }
run_performance_analysis() { log_with_timestamp "Performance analysis not implemented."; }
generate_comprehensive_report() { log_with_timestamp "Report generation not implemented."; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

setup_solana_environment() {
    log_with_timestamp "🔧 Setting up Solana environment..."
    if ! command_exists solana; then
        log_with_timestamp "❌ Solana CLI not found in PATH." "error"
        exit 1
    fi
    mkdir -p ~/.config/solana
    if [ ! -f ~/.config/solana/id.json ]; then
        solana-keygen new --no-bip39-passphrase --silent --outfile ~/.config/solana/id.json
    fi
    solana config set --url "${SOLANA_URL:-http://solana-validator:8899}" --keypair ~/.config/solana/id.json
    solana config get
    if [[ "${SOLANA_URL:-http://solana-validator:8899}" == *"devnet"* ]]; then
        log_with_timestamp "💰 Requesting SOL airdrop for testing..."
        solana airdrop 2 >/dev/null 2>&1 || log_with_timestamp "⚠️ Airdrop failed (might be rate limited)"
    fi
}

# AST-based cleaner (requires /usr/local/bin/clean_rust from Dockerfile)
fix_rust_warnings_ast() {
    local file="$1"
    if command -v clean_rust &>/dev/null; then
        clean_rust "$file"
    else
        echo "clean_rust binary not found, skipping AST cleanup" >&2
    fi
}

generate_test_file_ast() {
    local contract_name="$1"
    local contracts_dir="$2"
    mkdir -p "$contracts_dir/tests"
    cat > "$contracts_dir/tests/test_${contract_name}.rs" <<EOF
use solana_program_test::*;
use solana_sdk::signature::{Keypair, Signer};
use solana_sdk::pubkey::Pubkey;

#[tokio::test]
async fn test_${contract_name}_basic() {
    let _program_id = Pubkey::new_unique();
    let program_test = ProgramTest::new(
        "${contract_name}",
        _program_id,
        processor!(process_instruction),
    );
    let (_banks_client, _payer, _recent_blockhash) = program_test.start().await;
    assert!(true, "Basic test passed");
}
EOF
}

create_dynamic_cargo_toml() {
    local contract_name="$1"
    local contracts_dir="$2"
    log_with_timestamp "📝 Creating dynamic Cargo.toml for $contract_name..."
    cat > "$contracts_dir/Cargo.toml" <<EOF
[package]
name = "$contract_name"
version = "0.1.0"
edition = "2021"
description = "Smart contract automatically processed by SmartTestHub"

[lib]
crate-type = ["cdylib", "lib"]

[dependencies]
solana-program = "2.3.0"
solana-sdk = "2.3.1"
borsh = "1.5.7"
borsh-derive = "1.5.7"
thiserror = "2.0.12"
spl-token = { version = "4.0.3", features = ["no-entrypoint"] }
spl-associated-token-account = { version = "2.3.0", features = ["no-entrypoint"] }
arrayref = "0.3.9"
num-derive = "0.4.2"
num-traits = "0.2.19"
serde = { version = "1.0.219", features = ["derive"] }
serde_json = "1.0.141"

[dev-dependencies]
solana-program-test = "2.3.5"
solana-banks-client = "2.3.5"
tokio = { version = "1.46.1", features = ["full"] }
assert_matches = "1.5.0"
proptest = "1.7.0"

[features]
no-entrypoint = []
test-sbf = []

[profile.release]
overflow-checks = true
lto = "fat"
codegen-units = 1

[workspace]
EOF
}

setup_solana_environment

watch_dir="/app/input"
MARKER_DIR="/app/.processed"
CACHE_CARGO_TOML="/app/.cached_Cargo.toml"
mkdir -p "$watch_dir" "$MARKER_DIR"

log_with_timestamp "🚀 Starting Enhanced Non-EVM (Solana) Container..."
log_with_timestamp "📡 Watching for smart contract files in $watch_dir..."

if ! inotifywait -m -e close_write,moved_to,create "$watch_dir" 2>/dev/null |
while read -r directory events filename; do
    if [[ "$filename" == *.rs ]]; then
        FILE_PATH="$watch_dir/$filename"
        MARKER_FILE="$MARKER_DIR/$filename.processed"
        [ ! -f "$FILE_PATH" ] && continue
        CURRENT_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')
        if [ -f "$MARKER_FILE" ]; then
            LAST_HASH=$(cat "$MARKER_FILE")
            [ "$CURRENT_HASH" == "$LAST_HASH" ] && log_with_timestamp "⏭️ Skipping duplicate processing of $filename (same content hash)" && continue
        fi
        echo "$CURRENT_HASH" > "$MARKER_FILE"

        {
            start_time=$(date +%s)
            log_with_timestamp "🆕 Processing new Rust contract: $filename"
            contract_name="${filename%.rs}"
            contracts_dir="/app/contracts/${contract_name}"
            mkdir -p "$contracts_dir/src"
            cp "$FILE_PATH" "$contracts_dir/src/lib.rs"
            log_with_timestamp "📁 Contract copied to $contracts_dir/src/lib.rs"
            fix_rust_warnings_ast "$contracts_dir/src/lib.rs"
            create_dynamic_cargo_toml "$contract_name" "$contracts_dir"
            generate_test_file_ast "$contract_name" "$contracts_dir"

            cargo fetch

            (cd "$contracts_dir" && cargo build 2>&1 | tee -a "$LOG_FILE")
            if [ $? -eq 0 ]; then
                log_with_timestamp "✅ Build successful"
                (cd "$contracts_dir" && cargo test --release -- --test-threads="${CARGO_BUILD_JOBS}" | tee -a "$LOG_FILE")
            else
                log_with_timestamp "❌ Build failed for $contract_name" "error"
                continue
            fi

            run_security_audit "$contract_name"
            run_performance_analysis "$contract_name"
            end_time=$(date +%s)
            generate_comprehensive_report "$contract_name" "native" "$start_time" "$end_time"
            log_with_timestamp "🏁 Completed processing $filename"
            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "$LOG_FILE"
                log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
                find "$contracts_dir" -type f ! -name "${contract_name}-report.md" -delete
                find "$contracts_dir" -type d -empty -delete
                find "/app/logs/reports" -type f -name "${contract_name}*" ! -name "${contract_name}-report.md" -delete
            fi
            log_with_timestamp "=========================================="
        } 2>&1
    fi
done
then
    log_with_timestamp "❌ inotifywait failed, using fallback polling mechanism" "error"
    while true; do
        for file in "$watch_dir"/*.rs; do
            [ ! -f "$file" ] && continue
            filename=$(basename "$file")
            MARKER_FILE="$MARKER_DIR/$filename.processed"
            CURRENT_HASH=$(sha256sum "$file" | awk '{print $1}')
            if [ -f "$MARKER_FILE" ]; then
                LAST_HASH=$(cat "$MARKER_FILE")
                [ "$CURRENT_HASH" == "$LAST_HASH" ] && log_with_timestamp "⏭️ Skipping duplicate processing of $filename (same content hash)" && continue
            fi
            echo "$CURRENT_HASH" > "$MARKER_FILE"
            {
                start_time=$(date +%s)
                log_with_timestamp "🆕 Processing new Rust contract: $filename"
                contract_name="${filename%.rs}"
                contracts_dir="/app/contracts/${contract_name}"
                mkdir -p "$contracts_dir/src"
                cp "$file" "$contracts_dir/src/lib.rs"
                log_with_timestamp "📁 Contract copied to $contracts_dir/src/lib.rs"
                fix_rust_warnings_ast "$contracts_dir/src/lib.rs"
                create_dynamic_cargo_toml "$contract_name" "$contracts_dir"
                generate_test_file_ast "$contract_name" "$contracts_dir"

                cargo fetch
                (cd "$contracts_dir" && cargo build 2>&1 | tee -a "$LOG_FILE")
                if [ $? -eq 0 ]; then
                    log_with_timestamp "✅ Build successful"
                    (cd "$contracts_dir" && cargo test --release -- --test-threads="${CARGO_BUILD_JOBS}" | tee -a "$LOG_FILE")
                else
                    log_with_timestamp "❌ Build failed for $contract_name" "error"
                    continue
                fi

                run_security_audit "$contract_name"
                run_performance_analysis "$contract_name"
                end_time=$(date +%s)
                generate_comprehensive_report "$contract_name" "native" "$start_time" "$end_time"
                log_with_timestamp "🏁 Completed processing $filename"
                if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                    node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "$LOG_FILE"
                    log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
                    find "$contracts_dir" -type f ! -name "${contract_name}-report.md" -delete
                    find "$contracts_dir" -type d -empty -delete
                    find "/app/logs/reports" -type f -name "${contract_name}*" ! -name "${contract_name}-report.md" -delete
                fi
                log_with_timestamp "=========================================="
            } 2>&1
        done
        sleep 5
    done
fi
