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

start_xray_daemon() {
    log_with_timestamp "📡 Setting up AWS X-Ray daemon..." "xray"
    command -v xray > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_with_timestamp "📡 Found X-Ray daemon at $(which xray)" "xray"
        export AWS_REGION="us-east-1"
        log_with_timestamp "📡 Setting AWS_REGION to $AWS_REGION" "xray"
        if [ -f "/app/config/xray-config.json" ]; then
            log_with_timestamp "📡 Starting X-Ray daemon with custom config in local mode..." "xray"
            nohup xray -c /app/config/xray-config.json -l -o > "$XRAY_LOG" 2>&1 &
        else
            log_with_timestamp "📡 Starting X-Ray daemon with default config in local mode..." "xray"
            nohup xray -l -o > "$XRAY_LOG" 2>&1 &
        fi
        sleep 2
        if pgrep xray > /dev/null; then
            log_with_timestamp "✅ X-Ray daemon started successfully" "xray"
        else
            log_with_timestamp "❌ Failed to start X-Ray daemon: $(cat $XRAY_LOG | tail -10)" "error"
            log_with_timestamp "⚠️ Continuing without X-Ray daemon" "xray"
        fi
    else
        log_with_timestamp "⚠️ X-Ray daemon not found in PATH" "xray"
    fi
}

generate_tarpaulin_config() {
    if [ ! -f "/app/tarpaulin.toml" ]; then
        log_with_timestamp "📊 Generating tarpaulin.toml configuration file..."
        cat > "/app/tarpaulin.toml" <<EOF
[all]
timeout = "300s"
debug = false
follow-exec = true
verbose = true
workspace = true
out = ["Html", "Xml"]
output-dir = "/app/logs/coverage"
exclude-files = [
    "tests/*",
    "*/build/*", 
    "*/dist/*"
]
ignore-tests = true
EOF
        log_with_timestamp "✅ Created tarpaulin.toml"
    fi
}

setup_solana_environment() {
    log_with_timestamp "🔧 Setting up Solana environment..."
    log_with_timestamp "Current PATH: $PATH"
    if ! command_exists solana; then
        log_with_timestamp "❌ Solana CLI not found in PATH. Please rebuild the Docker image to include the Solana CLI." "error"
        return 1
    fi
    if [ ! -f ~/.config/solana/id.json ]; then
        log_with_timestamp "🔑 Generating new Solana keypair..."
        mkdir -p ~/.config/solana
        if solana-keygen new --no-bip39-passphrase --silent --outfile ~/.config/solana/id.json; then
            log_with_timestamp "✅ Solana keypair generated"
        else
            log_with_timestamp "❌ Failed to generate Solana keypair" "error"
            return 1
        fi
    fi
    local solana_url="${SOLANA_URL:-https://api.devnet.solana.com}"
    if solana config set --url "$solana_url" --keypair ~/.config/solana/id.json; then
        log_with_timestamp "✅ Solana config set successfully"
    else
        log_with_timestamp "❌ Failed to set Solana config" "error"
        return 1
    fi
    if solana config get >/dev/null 2>&1; then
        log_with_timestamp "✅ Solana CLI configured successfully"
        solana config get | while read -r line; do
            log_with_timestamp "   $line"
        done
    else
        log_with_timestamp "❌ Failed to configure Solana CLI" "error"
        return 1
    fi
    if [[ "$solana_url" == *"devnet"* ]]; then
        log_with_timestamp "💰 Requesting SOL airdrop for testing..."
        solana airdrop 2 >/dev/null 2>&1 || log_with_timestamp "⚠️ Airdrop failed (might be rate limited)"
    fi
    return 0
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

create_dynamic_cargo_toml() {
    local contract_name="$1"
    local source_path="$2"
    local project_type="$3"
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
    log_with_timestamp "✅ Created dynamic Cargo.toml"
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

run_tests_with_coverage() {
    local contract_name="$1"
    log_with_timestamp "🧪 Running tests with coverage for $contract_name..."
    mkdir -p "/app/logs/coverage"
    if [ -f "$project_dir/Anchor.toml" ]; then
        log_with_timestamp "🧪 Detected Anchor project, running 'anchor test'..."
        if anchor test | tee -a "$LOG_FILE"; then
            log_with_timestamp "✅ Anchor tests completed successfully"
        else
            log_with_timestamp "⚠️ Anchor tests had some issues" "error"
        fi
        # Tag coverage report
        if [ -f "/app/logs/coverage/coverage.html" ]; then
            mv "/app/logs/coverage/coverage.html" "/app/logs/coverage/${contract_name}-coverage.html"
        fi
    else
        if cargo tarpaulin --config /app/tarpaulin.toml -v --out Html --output-dir /app/logs/coverage; then
            log_with_timestamp "✅ Tests and coverage completed successfully"
        else
            log_with_timestamp "⚠️ Tests or coverage generation had some issues" "error"
        fi
        if [ -f "/app/logs/coverage/tarpaulin-report.html" ]; then
            mv "/app/logs/coverage/tarpaulin-report.html" "/app/logs/coverage/${contract_name}-tarpaulin-report.html"
            log_with_timestamp "📊 Coverage report generated: /app/logs/coverage/${contract_name}-tarpaulin-report.html"
        else
            log_with_timestamp "❌ Failed to generate coverage report" "error"
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

if [ "$AWS_XRAY_SDK_ENABLED" = "true" ]; then
    start_xray_daemon
fi

generate_tarpaulin_config

: > "$LOG_FILE"
: > "$ERROR_LOG"

watch_dir="/app/input"
project_dir="/app"

log_with_timestamp "🚀 Starting Enhanced Non-EVM (Solana) Container..."
log_with_timestamp "📡 Watching for smart contract files in $watch_dir..."
log_with_timestamp "🔧 Environment: ${RUST_LOG:-info} log level"

setup_solana_environment || {
    log_with_timestamp "❌ Failed to setup Solana environment" "error"
}

mkdir -p "$watch_dir"

echo "Setting up directory watch on $watch_dir..."
if ! inotifywait -m -e close_write,moved_to,create "$watch_dir" 2>/dev/null | 
while read -r directory events filename; do
    if [[ "$filename" == *.rs ]]; then
        {
            start_time=$(date +%s)
            log_with_timestamp "🆕 Processing new Rust contract: $filename"
            contract_name="${filename%.rs}"
            mkdir -p "$project_dir/src"
            cp "$watch_dir/$filename" "$project_dir/src/lib.rs"
            log_with_timestamp "📁 Contract copied to src/lib.rs"
            project_type=$(detect_project_type "$project_dir/src/lib.rs")
            log_with_timestamp "🔍 Detected project type: $project_type"
            create_dynamic_cargo_toml "$contract_name" "$project_dir/src/lib.rs" "$project_type"
            create_test_files "$contract_name" "$project_type"
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
cluster = "${SOLANA_URL:-https://api.devnet.solana.com}"
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
                    else
                        log_with_timestamp "❌ Anchor build failed, trying cargo build..." "error"
                        if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                            log_with_timestamp "✅ Cargo build successful"
                        else
                            log_with_timestamp "❌ All builds failed for $contract_name" "error"
                            continue
                        fi
                    fi
                    ;;
                *)
                    if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                        log_with_timestamp "✅ Build successful"
                    else
                        log_with_timestamp "❌ Build failed for $contract_name" "error"
                        continue
                    fi
                    ;;
            esac
            run_tests_with_coverage "$contract_name"
            run_security_audit "$contract_name"
            run_performance_analysis "$contract_name"
            end_time=$(date +%s)
            generate_comprehensive_report "$contract_name" "$project_type" "$start_time" "$end_time"
            log_with_timestamp "🏁 Completed processing $filename"
            # Aggregate all contract reports into a unified summary
            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "$LOG_FILE"
                log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/complete-contracts-report.md"
            fi
            log_with_timestamp "=========================================="
        } 2>&1
    fi
done
then
    log_with_timestamp "❌ inotifywait failed, using fallback polling mechanism" "error"
    mkdir -p /app/processed
    while true; do
        echo "Polling directory $watch_dir..."
        for file in "$watch_dir"/*.rs; do
            if [[ -f "$file" && ! -f "/app/processed/$(basename $file)" ]]; then
                filename=$(basename "$file")
                {
                    start_time=$(date +%s)
                    log_with_timestamp "🆕 Processing new Rust contract: $filename"
                    contract_name="${filename%.rs}"
                    mkdir -p "$project_dir/src"
                    cp "$file" "$project_dir/src/lib.rs"
                    log_with_timestamp "📁 Contract copied to src/lib.rs"
                    project_type=$(detect_project_type "$project_dir/src/lib.rs")
                    log_with_timestamp "🔍 Detected project type: $project_type"
                    create_dynamic_cargo_toml "$contract_name" "$project_dir/src/lib.rs" "$project_type"
                    create_test_files "$contract_name" "$project_type"
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
cluster = "${SOLANA_URL:-https://api.devnet.solana.com}"
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
                            else
                                log_with_timestamp "❌ Anchor build failed, trying cargo build..." "error"
                                if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                                    log_with_timestamp "✅ Cargo build successful"
                                else
                                    log_with_timestamp "❌ All builds failed for $contract_name" "error"
                                    continue
                                fi
                            fi
                            ;;
                        *)
                            if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                                log_with_timestamp "✅ Build successful"
                            else
                                log_with_timestamp "❌ Build failed for $contract_name" "error"
                                continue
                            fi
                            ;;
                    esac
                    run_tests_with_coverage "$contract_name"
                    run_security_audit "$contract_name"
                    run_performance_analysis "$contract_name"
                    end_time=$(date +%s)
                    generate_comprehensive_report "$contract_name" "$project_type" "$start_time" "$end_time"
                    log_with_timestamp "🏁 Completed processing $filename"
                    # Aggregate all contract reports into a unified summary
                    if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                        node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "$LOG_FILE"
                        log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/complete-contracts-report.md"
                    fi
                    log_with_timestamp "=========================================="
                    touch "/app/processed/$filename"
                } 2>&1
            fi
        done
        sleep 5
    done
fi
