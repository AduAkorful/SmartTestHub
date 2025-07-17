#!/bin/bash
set -e

LOG_FILE="/app/logs/test.log"
ERROR_LOG="/app/logs/error.log"
SECURITY_LOG="/app/logs/security/security-audit.log"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ERROR_LOG")" "$(dirname "$SECURITY_LOG")" \
  /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray

log_with_timestamp() {
    local message="$1"
    local log_type="${2:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    case $log_type in
        "error") echo "$timestamp ❌ $message" | tee -a "$LOG_FILE" "$ERROR_LOG" ;;
        "security") echo "$timestamp 🛡️ $message" | tee -a "$LOG_FILE" "$SECURITY_LOG" ;;
        *) echo "$timestamp $message" | tee -a "$LOG_FILE" ;;
    esac
}

watch_dir="/app/input"
MARKER_DIR="/app/.processed"
mkdir -p "$watch_dir" "$MARKER_DIR"

log_with_timestamp "🚀 Starting Enhanced StarkNet Container..."
log_with_timestamp "📡 Watching for Cairo smart contract files in $watch_dir..."

if ! inotifywait -m -e close_write,moved_to,create "$watch_dir" 2>/dev/null |
while read -r directory events filename; do
    if [[ "$filename" == *.cairo ]]; then
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
            CONTRACT_NAME="${filename%.cairo}"

            mkdir -p /app/src /app/tests
            cp "$FILE_PATH" /app/src/contract.cairo

            # Generate as many tests as possible based on contract analysis
            python3 /app/scripts/generate_starknet_tests.py /app/src/contract.cairo "/app/tests/test_${CONTRACT_NAME}.py"
            log_with_timestamp "🧪 Generated comprehensive tests for $CONTRACT_NAME"

            log_with_timestamp "🧪 Running pytest for $CONTRACT_NAME..."
            pytest --cov=src --cov-report=term --cov-report=xml:/app/logs/coverage/${CONTRACT_NAME}-coverage.xml --junitxml=/app/logs/reports/${CONTRACT_NAME}-junit.xml /app/tests/ | tee /app/logs/test.log

            log_with_timestamp "🔎 Running flake8 linter..."
            flake8 /app/src/contract.cairo > /app/logs/security/${CONTRACT_NAME}-flake8.log 2>&1 || true

            log_with_timestamp "🔒 Running bandit security scan..."
            bandit -r /app/src/contract.cairo -f txt -o /app/logs/security/${CONTRACT_NAME}-bandit.log || true

            log_with_timestamp "🛠️ Compiling contract with cairo-compile..."
            cairo-compile /app/src/contract.cairo --output /app/logs/${CONTRACT_NAME}-compiled.json > /app/logs/${CONTRACT_NAME}-compile.log 2>&1 || true

            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME" | tee -a "$LOG_FILE"
                log_with_timestamp "✅ Aggregated report generated: /app/logs/reports/${CONTRACT_NAME}-report.md"
            fi

            end_time=$(date +%s)
            log_with_timestamp "🏁 Completed processing $filename (processing time: \$((end_time-start_time))s)"
            log_with_timestamp "=========================================="
        } 2>&1
    fi
done
then
    log_with_timestamp "❌ inotifywait failed, using fallback polling mechanism" "error"
    while true; do
        for file in "$watch_dir"/*.cairo; do
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
                CONTRACT_NAME="${filename%.cairo}"

                mkdir -p /app/src /app/tests
                cp "$file" /app/src/contract.cairo

                python3 /app/scripts/generate_starknet_tests.py /app/src/contract.cairo "/app/tests/test_${CONTRACT_NAME}.py"
                log_with_timestamp "🧪 Generated comprehensive tests for $CONTRACT_NAME"

                log_with_timestamp "🧪 Running pytest for $CONTRACT_NAME..."
                pytest --cov=src --cov-report=term --cov-report=xml:/app/logs/coverage/${CONTRACT_NAME}-coverage.xml --junitxml=/app/logs/reports/${CONTRACT_NAME}-junit.xml /app/tests/ | tee /app/logs/test.log

                log_with_timestamp "🔎 Running flake8 linter..."
                flake8 /app/src/contract.cairo > /app/logs/security/${CONTRACT_NAME}-flake8.log 2>&1 || true

                log_with_timestamp "🔒 Running bandit security scan..."
                bandit -r /app/src/contract.cairo -f txt -o /app/logs/security/${CONTRACT_NAME}-bandit.log || true

                log_with_timestamp "🛠️ Compiling contract with cairo-compile..."
                cairo-compile /app/src/contract.cairo --output /app/logs/${CONTRACT_NAME}-compiled.json > /app/logs/${CONTRACT_NAME}-compile.log 2>&1 || true

                if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                    node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME" | tee -a "$LOG_FILE"
                    log_with_timestamp "✅ Aggregated report generated: /app/logs/reports/${CONTRACT_NAME}-report.md"
                fi

                end_time=$(date +%s)
                log_with_timestamp "🏁 Completed processing $filename (processing time: \$((end_time-start_time))s)"
                log_with_timestamp "=========================================="
            } 2>&1
        done
        sleep 5
    done
fi
