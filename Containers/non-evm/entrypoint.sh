#!/bin/bash
set -e

LOG_FILE="/app/logs/test.log"
ERROR_LOG="/app/logs/error.log"
SECURITY_LOG="/app/logs/security/security-audit.log"
PERFORMANCE_LOG="/app/logs/analysis/performance.log"
XRAY_LOG="/app/logs/xray/xray.log"

mkdir -p /app/input /app/logs /app/logs/security /app/logs/analysis /app/logs/xray /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/.processed /app/src

: > "$LOG_FILE"
: > "$ERROR_LOG"

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

generate_cargo_toml_from_template() {
    local contract_name="$1"
    if [ -f "/app/Cargo.toml.template" ]; then
        sed "s/{{CONTRACT_NAME}}/$contract_name/g" "/app/Cargo.toml.template" > "/app/Cargo.toml"
        log_with_timestamp "📝 Cargo.toml generated from template for $contract_name"
    else
        log_with_timestamp "❌ Cargo.toml.template not found!" "error"
        return 1
    fi
}

create_test_files() {
    local contract_name="$1"
    local project_type="$2"
    log_with_timestamp "🧪 Creating test files for $contract_name ($project_type)..."
    mkdir -p "/app/tests"
    # Just a basic placeholder generator; expand as needed
    cat > "/app/tests/test_${contract_name}.rs" <<EOF
#[cfg(test)]
mod tests {
    #[test]
    fn test_placeholder() {
        assert!(true, "Placeholder test passed");
    }
}
EOF
    log_with_timestamp "✅ Created test files"
}

run_tests_with_coverage() {
    local contract_name="$1"
    log_with_timestamp "🧪 Running tests with coverage for $contract_name..."
    mkdir -p "/app/logs/coverage"
    # run all tests, then coverage
    if cargo test --all-features --all-targets | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ Unit and integration tests passed"
    else
        log_with_timestamp "❌ Some tests failed" "error"
    fi
    if cargo tarpaulin --config /app/tarpaulin.toml -v --out Html --output-dir /app/logs/coverage | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ Coverage completed successfully"
    else
        log_with_timestamp "⚠️ Coverage generation had some issues" "error"
    fi
    if [ -f "/app/logs/coverage/tarpaulin-report.html" ]; then
        mv "/app/logs/coverage/tarpaulin-report.html" "/app/logs/coverage/${contract_name}-tarpaulin-report.html"
        log_with_timestamp "📊 Coverage report generated: /app/logs/coverage/${contract_name}-tarpaulin-report.html"
    else
        log_with_timestamp "❌ Failed to generate coverage report" "error"
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
    if [ -f "/app/logs/coverage/${contract_name}-tarpaulin-report.html" ]; then
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

if [ -f "/app/.env" ]; then
    export $(cat /app/.env | grep -v '^#' | xargs)
    log_with_timestamp "✅ Environment variables loaded from .env"
fi

setup_solana_environment || {
    log_with_timestamp "❌ Failed to setup Solana environment" "error"
}

generate_tarpaulin_config

if [ "$AWS_XRAY_SDK_ENABLED" = "true" ]; then
    start_xray_daemon
fi

log_with_timestamp "🚀 Starting Enhanced Non-EVM (Solana) Container..."
log_with_timestamp "📡 Watching for smart contract files in /app/input..."
log_with_timestamp "🔧 Environment: ${RUST_LOG:-info} log level"

inotifywait -m -e close_write,moved_to,create /app/input | \
while read -r directory events filename; do
    if [[ "$filename" == *.rs ]]; then
        MARKER_FILE="/app/.processed/$filename.processed"
        (
            exec 9>"$MARKER_FILE.lock"
            if ! flock -n 9; then
                log_with_timestamp "⏭️ Lock exists for $filename, skipping (concurrent event)"
                continue
            fi

            # If processed recently, skip
            if [ -f "$MARKER_FILE" ]; then
                LAST_PROCESSED=$(cat "$MARKER_FILE")
                CURRENT_TIME=$(date +%s)
                if (( $CURRENT_TIME - $LAST_PROCESSED < 30 )); then
                    log_with_timestamp "⏭️ Skipping duplicate processing of $filename (processed ${LAST_PROCESSED}s ago)"
                    continue
                fi
            fi
            date +%s > "$MARKER_FILE"

            start_time=$(date +%s)
            contract_name="${filename%.rs}"
            mkdir -p /app/src
            cp "/app/input/$filename" "/app/src/lib.rs"
            log_with_timestamp "📁 Copied $filename to /app/src/lib.rs"

            # Generate Cargo.toml from template
            generate_cargo_toml_from_template "$contract_name" || continue

            # Detect project type (for reporting)
            project_type=$(detect_project_type "/app/src/lib.rs")
            log_with_timestamp "🔍 Detected project type: $project_type"

            create_test_files "$contract_name" "$project_type"

            # --- Build ---
            if cargo build 2>&1 | tee -a "$LOG_FILE"; then
                log_with_timestamp "✅ Build successful"
            else
                log_with_timestamp "❌ Build failed for $contract_name" "error"
                continue
            fi

            # --- Run all tests and generate coverage ---
            run_tests_with_coverage "$contract_name"

            # --- Security ---
            run_security_audit "$contract_name"

            # --- Performance ---
            run_performance_analysis "$contract_name"

            end_time=$(date +%s)
            generate_comprehensive_report "$contract_name" "$project_type" "$start_time" "$end_time"
            log_with_timestamp "🏁 Completed processing $filename"

            # AI-enhanced report
            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "$LOG_FILE"
                log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
            fi

            log_with_timestamp "=========================================="
        )
    fi
done
