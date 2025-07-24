#!/bin/bash
set -e

LOG_FILE="/app/logs/test.log"
ERROR_LOG="/app/logs/error.log"
SECURITY_LOG="/app/logs/security/security-audit.log"
PERFORMANCE_LOG="/app/logs/performance/performance.log"
COVERAGE_LOG="/app/logs/coverage/coverage.log"
XRAY_LOG="/app/logs/xray/xray.log"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ERROR_LOG")" "$(dirname "$SECURITY_LOG")" \
  "$(dirname "$PERFORMANCE_LOG")" "$(dirname "$COVERAGE_LOG")" "$(dirname "$XRAY_LOG")" \
  /app/logs/coverage /app/logs/reports /app/logs/benchmarks /app/logs/security /app/logs/xray /app/contracts

log_with_timestamp() {
    local message="$1"
    local log_type="${2:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    case $log_type in
        "error") echo "$timestamp ❌ $message" | tee -a "$LOG_FILE" "$ERROR_LOG" ;;
        "security") echo "$timestamp 🛡️ $message" | tee -a "$LOG_FILE" "$SECURITY_LOG" ;;
        "performance") echo "$timestamp ⚡ $message" | tee -a "$LOG_FILE" "$PERFORMANCE_LOG" ;;
        "coverage") echo "$timestamp 📊 $message" | tee -a "$LOG_FILE" "$COVERAGE_LOG" ;;
        "xray") echo "$timestamp 📡 $message" | tee -a "$LOG_FILE" "$XRAY_LOG" ;;
        "success") echo "$timestamp ✅ $message" | tee -a "$LOG_FILE" ;;
        "warning") echo "$timestamp ⚠️ $message" | tee -a "$LOG_FILE" ;;
        *) echo "$timestamp 📝 $message" | tee -a "$LOG_FILE" ;;
    esac
}

run_comprehensive_tests() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "🔬 Running comprehensive test suite for $contract_name..."
    
    # Unit Tests
    log_with_timestamp "🧪 Running unit tests..."
    pytest --cov="$contracts_dir/src" \
          --cov-report=term \
          --cov-report=xml:/app/logs/coverage/${contract_name}-coverage.xml \
          --cov-report=html:/app/logs/coverage/${contract_name}-coverage-html \
          --junitxml=/app/logs/reports/${contract_name}-junit.xml \
          --timeout=30 \
          -v "$contracts_dir/tests/" || true
    
    # Integration Tests
    log_with_timestamp "🔄 Running integration tests..."
    pytest -m integration \
          --junitxml=/app/logs/reports/${contract_name}-integration.xml \
          "$contracts_dir/tests/" || true
    
    # Performance Tests
    log_with_timestamp "⚡ Running performance tests..."
    pytest -m performance \
          --junitxml=/app/logs/reports/${contract_name}-performance.xml \
          "$contracts_dir/tests/" || true
    
    # Security Tests
    log_with_timestamp "🛡️ Running security tests..."
    bandit -r "$contracts_dir/src/" -f txt -o /app/logs/security/${contract_name}-bandit.log || true
    
    # Static Analysis
    log_with_timestamp "🔍 Running static analysis..."
    mypy "$contracts_dir/src/" --strict > /app/logs/security/${contract_name}-mypy.log 2>&1 || true
    flake8 "$contracts_dir/src/" > /app/logs/security/${contract_name}-flake8.log 2>&1 || true
    
    # Code Formatting
    log_with_timestamp "✨ Running code formatters..."
    black "$contracts_dir/src/" --check > /app/logs/security/${contract_name}-black.log 2>&1 || true
    
    # TEAL Analysis
    log_with_timestamp "📝 Analyzing TEAL output..."
    python3 -c "
from pyteal import *
import sys
sys.path.append('$contracts_dir/src')
from contract import approval_program
teal = compileTeal(approval_program(), mode=Mode.Application, version=6)
print(teal)" > /app/logs/${contract_name}-teal.log 2>&1 || true

    # Generate performance metrics
    log_with_timestamp "📈 Generating performance metrics..." "performance"
    python3 -c "
import sys
sys.path.append('$contracts_dir/src')
from contract import approval_program
from pyteal import *
teal = compileTeal(approval_program(), mode=Mode.Application, version=6)
print(f'TEAL Program Size: {len(teal.split(\"\\n\"))} lines')
" > /app/logs/performance/${contract_name}-metrics.log 2>&1 || true
}

watch_dir="/app/input"
MARKER_DIR="/app/.processed"
mkdir -p "$watch_dir" "$MARKER_DIR"

log_with_timestamp "🚀 Starting Enhanced Algorand Container v2.0..."
log_with_timestamp "📡 Watching for PyTeal smart contract files in $watch_dir..."
log_with_timestamp "👤 Current User: AduAkorful"
log_with_timestamp "🕒 Start Time: 2025-07-24 11:21:52 UTC"

generate_import_line() {
    local contracts_dir="$1"
    if [ -f "$contracts_dir/src/contract.py" ]; then
        echo "from contract import approval_program"
    elif [ -f "$contracts_dir/contract.py" ]; then
        echo "from contract import approval_program"
    else
        echo "from contract import approval_program"
    fi
}

if ! inotifywait -m -e close_write,moved_to,create "$watch_dir" 2>/dev/null |
while read -r directory events filename; do
    if [[ "$filename" == *.py ]]; then
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
            CONTRACT_NAME="${filename%.py}"
            CONTRACTS_DIR="/app/contracts/${CONTRACT_NAME}"
            mkdir -p "$CONTRACTS_DIR/src" "$CONTRACTS_DIR/tests"

            cp "$FILE_PATH" "$CONTRACTS_DIR/src/contract.py"

            if [ ! -f "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py" ]; then
                cp /app/tests/test_contract_suite.py "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py"
                log_with_timestamp "🧪 Copied comprehensive test suite for $CONTRACT_NAME"
            fi

            run_comprehensive_tests "$CONTRACT_NAME" "$CONTRACTS_DIR"

            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                log_with_timestamp "📊 Generating comprehensive report..."
                node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME" | tee -a "$LOG_FILE"
                log_with_timestamp "✅ Report generated: /app/logs/reports/${CONTRACT_NAME}-report.md"
            fi

            end_time=$(date +%s)
            duration=$((end_time - start_time))
            log_with_timestamp "🏁 Completed processing $filename (duration: ${duration}s)" "success"
            log_with_timestamp "=========================================="
        } 2>&1
    fi
done
then
    log_with_timestamp "❌ inotifywait failed, using fallback polling mechanism" "error"
    while true; do
        for file in "$watch_dir"/*.py; do
            [ ! -f "$file" ] && continue
            filename=$(basename "$file")
            MARKER_FILE="$MARKER_DIR/$filename.processed"
            CURRENT_HASH=$(sha256sum "$file" | awk '{print $1}')
            if [ -f "$MARKER_FILE" ]; then
                LAST_HASH=$(cat "$MARKER_FILE")
                [ "$CURRENT_HASH" == "$LAST_HASH" ] && continue
            fi
            echo "$CURRENT_HASH" > "$MARKER_FILE"
            
            {
                start_time=$(date +%s)
                CONTRACT_NAME="${filename%.py}"
                CONTRACTS_DIR="/app/contracts/${CONTRACT_NAME}"
                mkdir -p "$CONTRACTS_DIR/src" "$CONTRACTS_DIR/tests"

                cp "$file" "$CONTRACTS_DIR/src/contract.py"

                if [ ! -f "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py" ]; then
                    cp /app/tests/test_contract_suite.py "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py"
                    log_with_timestamp "🧪 Copied comprehensive test suite for $CONTRACT_NAME"
                fi

                run_comprehensive_tests "$CONTRACT_NAME" "$CONTRACTS_DIR"

                if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                    log_with_timestamp "📊 Generating comprehensive report..."
                    node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME" | tee -a "$LOG_FILE"
                    log_with_timestamp "✅ Report generated: /app/logs/reports/${CONTRACT_NAME}-report.md"
                fi

                end_time=$(date +%s)
                duration=$((end_time - start_time))
                log_with_timestamp "🏁 Completed processing $filename (duration: ${duration}s)" "success"
                log_with_timestamp "=========================================="
            } 2>&1
        done
        sleep 5
    done
fi
