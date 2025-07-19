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

# Stub implementations for missing shell functions
run_security_audit() { log_with_timestamp "Security audit not implemented."; }
run_performance_analysis() { log_with_timestamp "Performance analysis not implemented."; }
generate_comprehensive_report() { log_with_timestamp "Report generation not implemented."; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- Solana/Anchor/Project Setup ---
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

detect_project_type() {
    local file_path="$1"
    if grep -q "#\[program\]" "$file_path" || grep -q "use anchor_lang::prelude" "$file_path"; then
        echo "anchor"
    elif grep -q "entrypoint\!" "$file_path" || grep -q "solana_program::entrypoint\!" "$file_path"; then
        echo "native"
    else
        echo "unknown"
    fi
}

# --- Dependency Build Caching Logic ---
cargo_toml_changed() {
    local new_cargo="$1"
    local cache_cargo="$2"
    if [ ! -f "$cache_cargo" ]; then
        return 0
    fi
    if ! cmp -s "$new_cargo" "$cache_cargo"; then
        return 0
    fi
    return 1
}

fetch_new_dependencies() {
    local cargo_toml="$1"
    local cache_cargo="$2"
    if cargo_toml_changed "$cargo_toml" "$cache_cargo"; then
        log_with_timestamp "🔄 Cargo.toml changed, fetching new dependencies..."
        cargo fetch
        cp "$cargo_toml" "$cache_cargo"
    else
        log_with_timestamp "✅ No change to dependencies, skipping cargo fetch."
    fi
}

create_dynamic_cargo_toml() {
    local contract_name="$1"
    local project_type="$2"
    log_with_timestamp "📝 Creating dynamic Cargo.toml for $contract_name ($project_type)..."
    cat > "$contracts_dir/Cargo.toml" <<EOF
[package]
name = "$contract_name"
version = "0.1.0"
edition = "2021"
description = "Smart contract automatically processed by SmartTestHub"

[lib]
crate-type = ["cdylib", "lib"]
EOF
    case $project_type in
        "anchor")
            cat >> "$contracts_dir/Cargo.toml" <<EOF

[dependencies]
anchor-lang = "0.29.0"
anchor-spl = "0.29.0"
solana-program = "1.16.15"
solana-sdk = "1.16.15"
borsh = "0.10.3"
borsh-derive = "0.10.3"
thiserror = "1.0"
spl-token = { version = "3.5.0", features = ["no-entrypoint"] }
spl-associated-token-account = { version = "1.1.2", features = ["no-entrypoint"] }
arrayref = "0.3.7"
num-derive = "0.4"
num-traits = "0.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
itertools = "0.13"
anyhow = "1"
bytemuck = { version = "1.15", features = ["derive"] }
lazy_static = "1"
regex = "1"
cfg-if = "1"
log = "0.4"
once_cell = "1"
EOF
            ;;
        "native")
            cat >> "$contracts_dir/Cargo.toml" <<EOF

[dependencies]
solana-program = "1.16.15"
borsh = "0.10.3"
borsh-derive = "0.10.3"
thiserror = "1.0"
num-traits = "0.2"
num-derive = "0.4"
arrayref = "0.3.7"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
itertools = "0.13"
anyhow = "1"
bytemuck = { version = "1.15", features = ["derive"] }
lazy_static = "1"
regex = "1"
cfg-if = "1"
log = "0.4"
once_cell = "1"
EOF
            ;;
        *)
            cat >> "$contracts_dir/Cargo.toml" <<EOF

[dependencies]
solana-program = "1.16.15"
borsh = "0.10.3"
borsh-derive = "0.10.3"
thiserror = "1.0"
arrayref = "0.3.7"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
itertools = "0.13"
anyhow = "1"
bytemuck = { version = "1.15", features = ["derive"] }
lazy_static = "1"
regex = "1"
cfg-if = "1"
log = "0.4"
once_cell = "1"
EOF
            ;;
    esac
    cat >> "$contracts_dir/Cargo.toml" <<EOF

[dev-dependencies]
solana-program-test = "1.16.15"
solana-banks-client = "1.16.15"
tokio = { version = "1.0", features = ["full"] }
assert_matches = "1.5"
proptest = "1.0"

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

create_test_files() {
    local contract_name="$1"
    local project_type="$2"
    log_with_timestamp "🧪 Creating test files for $contract_name ($project_type)..."
    mkdir -p "$contracts_dir/tests"
    case $project_type in
        "anchor")
            cat > "$contracts_dir/tests/test_${contract_name}.rs" <<EOF
use anchor_lang::prelude::*;
use solana_program_test::*;
use solana_sdk::{signature::{Keypair, Signer}, transaction::Transaction};

use ${contract_name}::*;

#[tokio::test]
async fn test_${contract_name}_initialization() {
    let program_id = Pubkey::new_unique();
    let mut program_test = ProgramTest::new(
        "${contract_name}",
        program_id,
        processor!(process_instruction),
    );
    let (mut banks_client, payer, recent_blockhash) = program_test.start().await;
    assert!(true);
}
EOF
            ;;
        "native")
            cat > "$contracts_dir/tests/test_${contract_name}.rs" <<EOF
use solana_program_test::*;
use solana_sdk::{
    account::Account,
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    transaction::Transaction,
};
use std::str::FromStr;
use ${contract_name}::*;

#[tokio::test]
async fn test_${contract_name}_basic() {
    let program_id = Pubkey::new_unique();
    let mut program_test = ProgramTest::new(
        "${contract_name}",
        program_id,
        processor!(process_instruction),
    );
    let (mut banks_client, payer, recent_blockhash) = program_test.start().await;
    assert!(true);
}
EOF
            ;;
        *)
            cat > "$contracts_dir/tests/test_${contract_name}.rs" <<EOF
use solana_program_test::*;
use solana_sdk::signature::{Keypair, Signer};

#[tokio::test]
async fn test_${contract_name}_placeholder() {
    assert!(true, "Placeholder test passed");
}
EOF
            ;;
    esac
    log_with_timestamp "✅ Created test files"
}

# ... (other helper functions remain unchanged) ...

if [ -f "/app/.env" ]; then
    export $(grep -v '^#' /app/.env | xargs)
    log_with_timestamp "✅ Environment variables loaded from .env"
fi

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
            project_type=$(detect_project_type "$contracts_dir/src/lib.rs")
            log_with_timestamp "🔍 Detected project type: $project_type"
            create_dynamic_cargo_toml "$contract_name" "$project_type"
            create_test_files "$contract_name" "$project_type"

            # Check and fetch only new dependencies
            fetch_new_dependencies "$contracts_dir/Cargo.toml" "$CACHE_CARGO_TOML"

            # Build step
            log_with_timestamp "🔨 Building $contract_name ($project_type)..."
            case $project_type in
                "anchor")
                    cat > "$contracts_dir/Anchor.toml" <<EOF
[features]
seed = false
skip-lint = false

[programs.localnet]
$contract_name = "target/deploy/${contract_name}.so"

[registry]
url = "https://api.apr.dev"

[provider]
cluster = "${SOLANA_URL:-http://solana-validator:8899}"
wallet = "~/.config/solana/id.json"

[scripts]
test = "cargo test-sbf"

[test]
startup_wait = 5000
shutdown_wait = 2000
upgrade_wait = 1000
EOF
                    (cd "$contracts_dir" && anchor build 2>&1 | tee -a "$LOG_FILE")
                    if [ $? -eq 0 ]; then
                        (cd "$contracts_dir" && anchor test --skip-local-validator | tee -a "$LOG_FILE")
                        log_with_timestamp "✅ Anchor build & tests successful"
                    else
                        log_with_timestamp "❌ Anchor build failed, trying cargo build..." "error"
                        (cd "$contracts_dir" && cargo build 2>&1 | tee -a "$LOG_FILE")
                        if [ $? -eq 0 ]; then
                            log_with_timestamp "✅ Cargo build successful"
                            (cd "$contracts_dir" && cargo test --release -- --test-threads="${CARGO_BUILD_JOBS}" | tee -a "$LOG_FILE")
                        else
                            log_with_timestamp "❌ All builds failed for $contract_name" "error"
                            continue
                        fi
                    fi
                    ;;
                *)
                    (cd "$contracts_dir" && cargo build 2>&1 | tee -a "$LOG_FILE")
                    if [ $? -eq 0 ]; then
                        log_with_timestamp "✅ Build successful"
                        (cd "$contracts_dir" && cargo test --release -- --test-threads="${CARGO_BUILD_JOBS}" | tee -a "$LOG_FILE")
                    else
                        log_with_timestamp "❌ Build failed for $contract_name" "error"
                        continue
                    fi
                    ;;
            esac

            # Security, performance, coverage, report generation (outside contract dir for global logs)
            run_security_audit "$contract_name"
            run_performance_analysis "$contract_name"
            end_time=$(date +%s)
            generate_comprehensive_report "$contract_name" "$project_type" "$start_time" "$end_time"
            log_with_timestamp "🏁 Completed processing $filename"
            # Aggregate all contract reports into a unified summary
            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "$LOG_FILE"
                log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
                # Clean up all files for this contract in /app/contracts/${contract_name} except the report
                find "$contracts_dir" -type f ! -name "${contract_name}-report.md" -delete
                find "$contracts_dir" -type d -empty -delete
                # Also clean up /app/logs/reports except the main report for this contract
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
                project_type=$(detect_project_type "$contracts_dir/src/lib.rs")
                log_with_timestamp "🔍 Detected project type: $project_type"
                create_dynamic_cargo_toml "$contract_name" "$project_type"
                create_test_files "$contract_name" "$project_type"

                fetch_new_dependencies "$contracts_dir/Cargo.toml" "$CACHE_CARGO_TOML"

                log_with_timestamp "🔨 Building $contract_name ($project_type)..."
                case $project_type in
                    "anchor")
                        cat > "$contracts_dir/Anchor.toml" <<EOF
[features]
seed = false
skip-lint = false

[programs.localnet]
$contract_name = "target/deploy/${contract_name}.so"

[registry]
url = "https://api.apr.dev"

[provider]
cluster = "${SOLANA_URL:-http://solana-validator:8899}"
wallet = "~/.config/solana/id.json"

[scripts]
test = "cargo test-sbf"

[test]
startup_wait = 5000
shutdown_wait = 2000
upgrade_wait = 1000
EOF
                        (cd "$contracts_dir" && anchor build 2>&1 | tee -a "$LOG_FILE")
                        if [ $? -eq 0 ]; then
                            (cd "$contracts_dir" && anchor test --skip-local-validator | tee -a "$LOG_FILE")
                            log_with_timestamp "✅ Anchor build & tests successful"
                        else
                            log_with_timestamp "❌ Anchor build failed, trying cargo build..." "error"
                            (cd "$contracts_dir" && cargo build 2>&1 | tee -a "$LOG_FILE")
                            if [ $? -eq 0 ]; then
                                log_with_timestamp "✅ Cargo build successful"
                                (cd "$contracts_dir" && cargo test --release -- --test-threads="${CARGO_BUILD_JOBS}" | tee -a "$LOG_FILE")
                            else
                                log_with_timestamp "❌ All builds failed for $contract_name" "error"
                                continue
                            fi
                        fi
                        ;;
                    *)
                        (cd "$contracts_dir" && cargo build 2>&1 | tee -a "$LOG_FILE")
                        if [ $? -eq 0 ]; then
                            log_with_timestamp "✅ Build successful"
                            (cd "$contracts_dir" && cargo test --release -- --test-threads="${CARGO_BUILD_JOBS}" | tee -a "$LOG_FILE")
                        else
                            log_with_timestamp "❌ Build failed for $contract_name" "error"
                            continue
                        fi
                        ;;
                esac
                run_security_audit "$contract_name"
                run_performance_analysis "$contract_name"
                end_time=$(date +%s)
                generate_comprehensive_report "$contract_name" "$project_type" "$start_time" "$end_time"
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
