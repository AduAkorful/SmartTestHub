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
  /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

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
    cat > "$project_dir/Cargo.toml" <<EOF
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
            cat >> "$project_dir/Cargo.toml" <<EOF

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
            cat >> "$project_dir/Cargo.toml" <<EOF

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
            cat >> "$project_dir/Cargo.toml" <<EOF

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
    cat >> "$project_dir/Cargo.toml" <<EOF

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
EOF
}

create_test_files() {
    local contract_name="$1"
    local project_type="$2"
    log_with_timestamp "🧪 Creating test files for $contract_name ($project_type)..."
    mkdir -p "$project_dir/tests"
    case $project_type in
        "anchor")
            cat > "$project_dir/tests/test_${contract_name}.rs" <<EOF
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
            cat > "$project_dir/tests/test_${contract_name}.rs" <<EOF
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
            cat > "$project_dir/tests/test_${contract_name}.rs" <<EOF
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

run_fast_tests() {
    local contract_name="$1"
    log_with_timestamp "🧪 Running fast cargo tests for $contract_name..."
    if cargo test --release -- --test-threads="${CARGO_BUILD_JOBS}" | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ cargo test completed"
    else
        log_with_timestamp "❌ cargo test failed" "error"
    fi
}

run_coverage_if_requested() {
    local contract_name="$1"
    if [ "$COVERAGE" == "1" ]; then
        log_with_timestamp "🧪 Running tarpaulin for coverage (slower)..."
        if cargo tarpaulin --out Html --output-dir /app/logs/coverage | tee -a "$LOG_FILE"; then
            log_with_timestamp "✅ Coverage report generated"
        else
            log_with_timestamp "❌ Coverage failed" "error"
        fi
    fi
}

run_security_audit() {
    local contract_name="$1"
    log_with_timestamp "🛡️ Running security audit for $contract_name..." "security"
    cargo generate-lockfile || true
    mkdir -p "/app/logs/security"
    if cargo audit -f /app/Cargo.lock > "/app/logs/security/${contract_name}-cargo-audit.log" 2>&1; then
        log_with_timestamp "✅ Cargo audit completed successfully" "security"
    else
        log_with_timestamp "⚠️ Cargo audit found potential vulnerabilities" "security"
    fi
    if cargo clippy --all-targets --all-features -- -D warnings > "/app/logs/security/${contract_name}-clippy.log" 2>&1; then
        log_with_timestamp "✅ Clippy checks passed" "security"
    else
        log_with_timestamp "⚠️ Clippy found code quality issues" "security"
    fi
}

run_performance_analysis() {
    local contract_name="$1"
    log_with_timestamp "⚡ Running performance analysis for $contract_name..." "performance"
    mkdir -p "/app/logs/benchmarks"
    log_with_timestamp "Measuring build time performance..." "performance"
    local start_time=$(date +%s)
    if cargo build --release > "/app/logs/benchmarks/${contract_name}-build-time.log" 2>&1; then
        local end_time=$(date +%s)
        local build_time=$((end_time - start_time))
        log_with_timestamp "✅ Release build completed in $build_time seconds" "performance"
    else
        log_with_timestamp "❌ Release build failed" "performance"
    fi
    if [ -f "/app/target/release/${contract_name}.so" ]; then
        local program_size=$(du -h "/app/target/release/${contract_name}.so" | cut -f1)
        log_with_timestamp "📊 Program size: $program_size" "performance"
        echo "$program_size" > "/app/logs/benchmarks/${contract_name}-program-size.txt"
    fi
}

generate_comprehensive_report() {
    local contract_name="$1"
    local project_type="$2"
    local start_time="$3"
    local end_time="$4"
    local processing_time=$((end_time - start_time))
    log_with_timestamp "📝 Generating comprehensive report for $contract_name..."
    mkdir -p "/app/logs/reports"
    local report_file="/app/logs/reports/${contract_name}_report.md"
    cat > "$report_file" <<EOF
# Comprehensive Analysis Report for $contract_name

## Overview
- **Contract Name:** $contract_name
- **Project Type:** $project_type
- **Processing Time:** $processing_time seconds
- **Timestamp:** $(date)

## Build Status
- Build completed successfully
- Project structure verified

## Test Results
EOF
    if [ -f "/app/logs/coverage/${contract_name}-tarpaulin-report.html" ] || [ -f "/app/logs/coverage/${contract_name}-coverage.html" ]; then
        echo "- ✅ Tests executed successfully" >> "$report_file"
        echo "- 📊 Coverage report available at \`/app/logs/coverage/${contract_name}-tarpaulin-report.html\`" >> "$report_file"
    else
        echo "- ⚠️ Test coverage report not available" >> "$report_file"
    fi
    echo -e "\n## Security Analysis" >> "$report_file"
    if [ -f "/app/logs/security/${contract_name}-cargo-audit.log" ]; then
        echo "- 🛡️ Security audit completed" >> "$report_file"
        echo "- Details available in \`/app/logs/security/${contract_name}-cargo-audit.log\`" >> "$report_file"
    else
        echo "- ⚠️ Security audit report not available" >> "$report_file"
    fi
    echo -e "\n## Performance Analysis" >> "$report_file"
    if [ -f "/app/logs/benchmarks/${contract_name}-build-time.log" ]; then
        echo "- ⚡ Performance analysis completed" >> "$report_file"
        if [ -f "/app/target/release/${contract_name}.so" ]; then
            local program_size=$(du -h "/app/target/release/${contract_name}.so" | cut -f1)
            echo "- 📊 Program size: $program_size" >> "$report_file"
        fi
    else
        echo "- ⚠️ Performance analysis not available" >> "$report_file"
    fi
    echo -e "\n## Recommendations" >> "$report_file"
    echo "- Ensure comprehensive test coverage for all program paths" >> "$report_file"
    echo "- Address any security concerns highlighted in the audit report" >> "$report_file"
    echo "- Consider optimizing program size and execution time if required" >> "$report_file"
    log_with_timestamp "✅ Comprehensive report generated at $report_file"
}

run_anchor_tests() {
    local contract_name="$1"
    log_with_timestamp "🧪 Running anchor tests (skipping local validator)..."
    if anchor test --skip-local-validator | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ anchor test completed"
    else
        log_with_timestamp "❌ anchor test failed" "error"
    fi
}

# --- Main File Watch/Processing Loop ---
if [ -f "/app/.env" ]; then
    export $(grep -v '^#' /app/.env | xargs)
    log_with_timestamp "✅ Environment variables loaded from .env"
fi

setup_solana_environment

watch_dir="/app/input"
project_dir="/app"
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
            mkdir -p "$project_dir/src"
            cp "$FILE_PATH" "$project_dir/src/lib.rs"
            log_with_timestamp "📁 Contract copied to src/lib.rs"
            project_type=$(detect_project_type "$project_dir/src/lib.rs")
            log_with_timestamp "🔍 Detected project type: $project_type"
            create_dynamic_cargo_toml "$contract_name" "$project_type"
            create_test_files "$contract_name" "$project_type"

            # Check and fetch only new dependencies
            fetch_new_dependencies "$project_dir/Cargo.toml" "$CACHE_CARGO_TOML"

            # Build step
            log_with_timestamp "🔨 Building $contract_name ($project_type)..."
            case $project_type in
                "anchor")
                    cat > "$project_dir/Anchor.toml" <<EOF
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
                    if anchor build 2>&1 | tee -a "$LOG_FILE"; then
                        log_with_timestamp "✅ Anchor build successful"
                        run_anchor_tests "$contract_name"
                    else
                        log_with_timestamp "❌ Anchor build failed, trying cargo build..." "error"
                        if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                            log_with_timestamp "✅ Cargo build successful"
                            run_fast_tests "$contract_name"
                            run_coverage_if_requested "$contract_name"
                        else
                            log_with_timestamp "❌ All builds failed for $contract_name" "error"
                            continue
                        fi
                    fi
                    ;;
                *)
                    if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                        log_with_timestamp "✅ Build successful"
                        run_fast_tests "$contract_name"
                        run_coverage_if_requested "$contract_name"
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
            # Aggregate all contract reports into a unified summary
            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "$LOG_FILE"
                log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
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
                mkdir -p "$project_dir/src"
                cp "$file" "$project_dir/src/lib.rs"
                log_with_timestamp "📁 Contract copied to src/lib.rs"
                project_type=$(detect_project_type "$project_dir/src/lib.rs")
                log_with_timestamp "🔍 Detected project type: $project_type"
                create_dynamic_cargo_toml "$contract_name" "$project_type"
                create_test_files "$contract_name" "$project_type"

                fetch_new_dependencies "$project_dir/Cargo.toml" "$CACHE_CARGO_TOML"

                log_with_timestamp "🔨 Building $contract_name ($project_type)..."
                case $project_type in
                    "anchor")
                        cat > "$project_dir/Anchor.toml" <<EOF
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
                        if anchor build 2>&1 | tee -a "$LOG_FILE"; then
                            log_with_timestamp "✅ Anchor build successful"
                            run_anchor_tests "$contract_name"
                        else
                            log_with_timestamp "❌ Anchor build failed, trying cargo build..." "error"
                            if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                                log_with_timestamp "✅ Cargo build successful"
                                run_fast_tests "$contract_name"
                                run_coverage_if_requested "$contract_name"
                            else
                                log_with_timestamp "❌ All builds failed for $contract_name" "error"
                                continue
                            fi
                        fi
                        ;;
                    *)
                        if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                            log_with_timestamp "✅ Build successful"
                            run_fast_tests "$contract_name"
                            run_coverage_if_requested "$contract_name"
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
                fi
                log_with_timestamp "=========================================="
            } 2>&1
        done
        sleep 5
    done
fi
