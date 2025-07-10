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

MARKER_DIR="/app/.processed"
mkdir -p "$MARKER_DIR"

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

# ... (rest of your setup and function definitions unchanged) ...

watch_dir="/app/input"
project_dir="/app"

log_with_timestamp "🚀 Starting Enhanced Non-EVM (Solana) Container..."
log_with_timestamp "📡 Watching for smart contract files in $watch_dir..."
log_with_timestamp "🔧 Environment: ${RUST_LOG:-info} log level"

mkdir -p "$watch_dir"

echo "Setting up directory watch on $watch_dir..."
inotifywait -m -e close_write,moved_to,create "$watch_dir" 2>/dev/null | 
while read -r directory events filename; do
    if [[ "$filename" == *.rs ]]; then
        MARKER_FILE="$MARKER_DIR/$filename.processed"
        (
          exec 9>"$MARKER_FILE.lock"
          if ! flock -n 9; then
              log_with_timestamp "⏭️ Lock exists for $filename, skipping (concurrent event)"
              continue
          fi

          if [ -f "$MARKER_FILE" ]; then
              LAST_PROCESSED=$(cat "$MARKER_FILE")
              CURRENT_TIME=$(date +%s)
              if (( $CURRENT_TIME - $LAST_PROCESSED < 30 )); then
                  log_with_timestamp "⏭️ Skipping duplicate processing of $filename (processed ${LAST_PROCESSED}s ago)"
                  continue
              fi
          fi
          date +%s > "$MARKER_FILE"

          # ... (the rest of your contract processing logic here, unchanged) ...
        )
    fi
done
