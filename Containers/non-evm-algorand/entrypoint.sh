#!/bin/bash
set -e

LOG_DIR="${LOG_DIR:-/app/logs}"
WATCH_DIR="${WATCH_DIR:-/app/input}"
MARKER_DIR="/app/.processed"

# Ensure directories exist
mkdir -p "$LOG_DIR"/{coverage,reports,security,performance}
mkdir -p "$WATCH_DIR" "$MARKER_DIR"

log_with_timestamp() {
    local message="$1"
    local log_type="${2:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $message" | tee -a "$LOG_DIR/test.log"
}

process_file() {
    local FILE_PATH="$1"
    local filename=$(basename "$FILE_PATH")
    local start_time=$(date +%s)
    
    log_with_timestamp "🔄 Processing $filename..."
    
    # Run the test suite
    python3 -m src.utils.test_runner "$FILE_PATH" "$LOG_DIR"
    
    # Run log aggregation
    node /app/scripts/aggregate-all-logs.js "${filename%.py}"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_with_timestamp "✅ Completed processing $filename (duration: ${duration}s)" "success"
}

log_with_timestamp "🚀 Starting Algorand Smart Contract Testing Container"
log_with_timestamp "📡 Watching directory: $WATCH_DIR"

# Main file watching loop
if ! inotifywait -m -e close_write,moved_to,create "$WATCH_DIR" 2>/dev/null |
while read -r directory events filename; do
    if [[ "$filename" =~ \.py$ ]]; then
        FILE_PATH="$WATCH_DIR/$filename"
        MARKER_FILE="$MARKER_DIR/$filename.processed"
        [ ! -f "$FILE_PATH" ] && continue
        
        # Check if file has changed
        CURRENT_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')
        if [ -f "$MARKER_FILE" ]; then
            LAST_HASH=$(cat "$MARKER_FILE")
            [ "$CURRENT_HASH" == "$LAST_HASH" ] && continue
        fi
        echo "$CURRENT_HASH" > "$MARKER_FILE"
        
        process_file "$FILE_PATH"
    fi
done
then
    log_with_timestamp "⚠️ inotifywait failed, using fallback polling" "warning"
    while true; do
        for file in "$WATCH_DIR"/*.py; do
            [ ! -f "$file" ] && continue
            filename=$(basename "$file")
            MARKER_FILE="$MARKER_DIR/$filename.processed"
            CURRENT_HASH=$(sha256sum "$file" | awk '{print $1}')
            [ -f "$MARKER_FILE" ] && [ "$CURRENT_HASH" == "$(cat "$MARKER_FILE")" ] && continue
            
            echo "$CURRENT_HASH" > "$MARKER_FILE"
            process_file "$file"
        done
        sleep 5
    done
fi
