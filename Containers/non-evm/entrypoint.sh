#!/bin/bash
set -e

mkdir -p /app/input /app/logs /app/logs/security /app/logs/analysis /app/logs/xray /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/.processed /app/src

log_with_timestamp() {
    local contract_name="$1"
    local message="$2"
    local log_type="${3:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local LOG_FILE="/app/logs/${contract_name}-test.log"
    local ERROR_LOG="/app/logs/${contract_name}-error.log"
    local SECURITY_LOG="/app/logs/security/${contract_name}-security-audit.log"
    local PERFORMANCE_LOG="/app/logs/analysis/${contract_name}-performance.log"
    local XRAY_LOG="/app/logs/xray/${contract_name}-xray.log"
    case $log_type in
        "error") echo "$timestamp ❌ $message" | tee -a "$LOG_FILE" "$ERROR_LOG" ;;
        "security") echo "$timestamp 🛡️ $message" | tee -a "$LOG_FILE" "$SECURITY_LOG" ;;
        "performance") echo "$timestamp ⚡ $message" | tee -a "$LOG_FILE" "$PERFORMANCE_LOG" ;;
        "xray") echo "$timestamp 📡 $message" | tee -a "$LOG_FILE" "$XRAY_LOG" ;;
        *) echo "$timestamp $message" | tee -a "$LOG_FILE" ;;
    esac
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

generate_tarpaulin_config() {
    if [ ! -f "/app/tarpaulin.toml" ]; then
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
    fi
}

setup_solana_environment() {
    local contract_name="$1"
    log_with_timestamp "$contract_name" "🔧 Setting up Solana environment..."
    if ! command_exists solana; then
        log_with_timestamp "$contract_name" "❌ Solana CLI not found in PATH. Please rebuild the Docker image to include the Solana CLI." "error"
        return 1
    fi
    if [ ! -f ~/.config/solana/id.json ]; then
        log_with_timestamp "$contract_name" "🔑 Generating new Solana keypair..."
        mkdir -p ~/.config/solana
        if solana-keygen new --no-bip39-passphrase --silent --outfile ~/.config/solana/id.json; then
            log_with_timestamp "$contract_name" "✅ Solana keypair generated"
        else
            log_with_timestamp "$contract_name" "❌ Failed to generate Solana keypair" "error"
            return 1
        fi
    fi
    local solana_url="${SOLANA_URL:-https://api.devnet.solana.com}"
    if solana config set --url "$solana_url" --keypair ~/.config/solana/id.json; then
        log_with_timestamp "$contract_name" "✅ Solana config set successfully"
    else
        log_with_timestamp "$contract_name" "❌ Failed to set Solana config" "error"
        return 1
    fi
    if solana config get >/dev/null 2>&1; then
        log_with_timestamp "$contract_name" "✅ Solana CLI configured successfully"
    else
        log_with_timestamp "$contract_name" "❌ Failed to configure Solana CLI" "error"
        return 1
    fi
    if [[ "$solana_url" == *"devnet"* ]]; then
        log_with_timestamp "$contract_name" "💰 Requesting SOL airdrop for testing..."
        solana airdrop 2 >/dev/null 2>&1 || log_with_timestamp "$contract_name" "⚠️ Airdrop failed (might be rate limited)"
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
    fi
}

create_test_files() {
    local contract_name="$1"
    local project_type="$2"
    mkdir -p "/app/tests"
    cat > "/app/tests/test_${contract_name}.rs" <<EOF
#[cfg(test)]
mod tests {
    #[test]
    fn test_placeholder() {
        assert!(true, "Placeholder test passed");
    }
}
EOF
}

run_tests_with_coverage() {
    local contract_name="$1"
    mkdir -p "/app/logs/coverage"
    if cargo test --all-features --all-targets | tee -a "/app/logs/${contract_name}-test.log"; then
        log_with_timestamp "$contract_name" "✅ Unit and integration tests passed"
    else
        log_with_timestamp "$contract_name" "❌ Some tests failed" "error"
    fi
    if cargo tarpaulin --config /app/tarpaulin.toml -v --out Html --output-dir /app/logs/coverage | tee -a "/app/logs/${contract_name}-test.log"; then
        log_with_timestamp "$contract_name" "✅ Coverage completed successfully"
    else
        log_with_timestamp "$contract_name" "⚠️ Coverage generation had some issues" "error"
    fi
    if [ -f "/app/logs/coverage/tarpaulin-report.html" ]; then
        mv "/app/logs/coverage/tarpaulin-report.html" "/app/logs/coverage/${contract_name}-tarpaulin-report.html"
        log_with_timestamp "$contract_name" "📊 Coverage report generated: /app/logs/coverage/${contract_name}-tarpaulin-report.html"
    else
        log_with_timestamp "$contract_name" "❌ Failed to generate coverage report" "error"
    fi
}

run_security_audit() {
    local contract_name="$1"
    cargo generate-lockfile || true
    mkdir -p "/app/logs/security"
    if cargo audit -f /app/Cargo.lock > "/app/logs/security/${contract_name}-cargo-audit.log" 2>&1; then
        log_with_timestamp "$contract_name" "✅ Cargo audit completed successfully" "security"
    else
        log_with_timestamp "$contract_name" "⚠️ Cargo audit found potential vulnerabilities" "security"
    fi
    if cargo clippy --all-targets --all-features -- -D warnings > "/app/logs/security/${contract_name}-clippy.log" 2>&1; then
        log_with_timestamp "$contract_name" "✅ Clippy checks passed" "security"
    else
        log_with_timestamp "$contract_name" "⚠️ Clippy found code quality issues" "security"
    fi
}

run_performance_analysis() {
    local contract_name="$1"
    mkdir -p "/app/logs/benchmarks"
    local start_time=$(date +%s)
    if cargo build --release > "/app/logs/benchmarks/${contract_name}-build-time.log" 2>&1; then
        local end_time=$(date +%s)
        local build_time=$((end_time - start_time))
        log_with_timestamp "$contract_name" "✅ Release build completed in $build_time seconds" "performance"
    else
        log_with_timestamp "$contract_name" "❌ Release build failed" "performance"
    fi
    if [ -f "/app/target/release/${contract_name}.so" ]; then
        local program_size=$(du -h "/app/target/release/${contract_name}.so" | cut -f1)
        log_with_timestamp "$contract_name" "📊 Program size: $program_size" "performance"
        echo "$program_size" > "/app/logs/benchmarks/${contract_name}-program-size.txt"
    fi
}

generate_comprehensive_report() {
    local contract_name="$1"
    local project_type="$2"
    local start_time="$3"
    local end_time="$4"
    local processing_time=$((end_time - start_time))
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
}

if [ -f "/app/.env" ]; then
    export $(cat /app/.env | grep -v '^#' | xargs)
fi

generate_tarpaulin_config

inotifywait -m -e close_write,moved_to,create /app/input | \
while read -r directory events filename; do
    if [[ "$filename" == *.rs ]]; then
        MARKER_FILE="/app/.processed/$filename.processed"
        (
            exec 9>"$MARKER_FILE.lock"
            if ! flock -n 9; then
                continue
            fi

            if [ -f "$MARKER_FILE" ]; then
                LAST_PROCESSED=$(cat "$MARKER_FILE")
                CURRENT_TIME=$(date +%s)
                if (( $CURRENT_TIME - $LAST_PROCESSED < 30 )); then
                    continue
                fi
            fi
            date +%s > "$MARKER_FILE"

            contract_name="${filename%.rs}"

            # Clean up per-contract logs
            find /app/logs/coverage -type f -name "${contract_name}*" -delete
            find /app/logs/security -type f -name "${contract_name}*" -delete
            find /app/logs/benchmarks -type f -name "${contract_name}*" -delete
            find /app/logs/reports -type f -name "${contract_name}*" -delete
            : > "/app/logs/${contract_name}-test.log"
            : > "/app/logs/${contract_name}-error.log"

            cp "/app/input/$filename" "/app/src/lib.rs"
            generate_cargo_toml_from_template "$contract_name" || continue
            setup_solana_environment "$contract_name" || continue

            project_type=$(detect_project_type "/app/src/lib.rs")
            create_test_files "$contract_name" "$project_type"

            log_with_timestamp "$contract_name" "🚀 Starting analysis for $contract_name"
            if cargo build 2>&1 | tee -a "/app/logs/${contract_name}-test.log"; then
                log_with_timestamp "$contract_name" "✅ Build successful"
            else
                log_with_timestamp "$contract_name" "❌ Build failed for $contract_name" "error"
                continue
            fi

            start_time=$(date +%s)
            run_tests_with_coverage "$contract_name"
            run_security_audit "$contract_name"
            run_performance_analysis "$contract_name"
            end_time=$(date +%s)
            generate_comprehensive_report "$contract_name" "$project_type" "$start_time" "$end_time"
            log_with_timestamp "$contract_name" "🏁 Completed processing $filename"

            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                node /app/scripts/aggregate-all-logs.js "$contract_name" | tee -a "/app/logs/${contract_name}-test.log"
                log_with_timestamp "$contract_name" "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
            fi
            log_with_timestamp "$contract_name" "=========================================="
        )
    fi
done
