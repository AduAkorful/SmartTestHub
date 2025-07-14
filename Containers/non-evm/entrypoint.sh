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

# ... (other functions unchanged) ...

if [ "$AWS_XRAY_SDK_ENABLED" = "true" ]; then
    start_xray_daemon
fi

generate_tarpaulin_config

: > "$LOG_FILE"
: > "$ERROR_LOG"

watch_dir="/app/input"
project_dir="/app"
MARKER_DIR="/app/.processed"
mkdir -p "$watch_dir"
mkdir -p "$MARKER_DIR"

log_with_timestamp "🚀 Starting Enhanced Non-EVM (Solana) Container..."
log_with_timestamp "📡 Watching for smart contract files in $watch_dir..."
log_with_timestamp "🔧 Environment: ${RUST_LOG:-info} log level"

setup_solana_environment || {
    log_with_timestamp "❌ Failed to setup Solana environment" "error"
}

echo "Setting up directory watch on $watch_dir..."
if ! inotifywait -m -e close_write,moved_to,create "$watch_dir" 2>/dev/null | 
while read -r directory events filename; do
    if [[ "$filename" == *.rs ]]; then
        FILE_PATH="$watch_dir/$filename"
        MARKER_FILE="$MARKER_DIR/$filename.processed"
        if [ ! -f "$FILE_PATH" ]; then
            continue
        fi
        CURRENT_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')
        if [ -f "$MARKER_FILE" ]; then
            LAST_HASH=$(cat "$MARKER_FILE")
            if [ "$CURRENT_HASH" == "$LAST_HASH" ]; then
                log_with_timestamp "⏭️ Skipping duplicate processing of $filename (same content hash)"
                continue
            fi
        fi
        echo "$CURRENT_HASH" > "$MARKER_FILE"
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
                log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
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
            if [[ -f "$file" ]]; then
                filename=$(basename "$file")
                MARKER_FILE="$MARKER_DIR/$filename.processed"
                CURRENT_HASH=$(sha256sum "$file" | awk '{print $1}')
                if [ -f "$MARKER_FILE" ]; then
                    LAST_HASH=$(cat "$MARKER_FILE")
                    if [ "$CURRENT_HASH" == "$LAST_HASH" ]; then
                        log_with_timestamp "⏭️ Skipping duplicate processing of $filename (same content hash)"
                        continue
                    fi
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
                        log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.md"
                    fi
                    log_with_timestamp "=========================================="
                } 2>&1
            fi
        done
        sleep 5
    done
fi
