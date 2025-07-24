#!/bin/bash
set -e

# Enhanced logging setup with color support
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Expanded log directory structure
LOG_FILE="/app/logs/test.log"
ERROR_LOG="/app/logs/error.log"
SECURITY_LOG="/app/logs/security/security-audit.log"
PERFORMANCE_LOG="/app/logs/performance/performance.log"
COVERAGE_LOG="/app/logs/coverage/coverage.log"
XRAY_LOG="/app/logs/xray/xray.log"
INTEGRATION_LOG="/app/logs/integration/integration.log"
METRICS_LOG="/app/logs/metrics/metrics.log"
DEBUG_LOG="/app/logs/debug/debug.log"

# Create all required directories
declare -a LOG_DIRS=(
    "$(dirname "$LOG_FILE")"
    "$(dirname "$ERROR_LOG")"
    "$(dirname "$SECURITY_LOG")"
    "$(dirname "$PERFORMANCE_LOG")"
    "$(dirname "$COVERAGE_LOG")"
    "$(dirname "$XRAY_LOG")"
    "$(dirname "$INTEGRATION_LOG")"
    "$(dirname "$METRICS_LOG")"
    "$(dirname "$DEBUG_LOG")"
    "/app/logs/coverage"
    "/app/logs/reports"
    "/app/logs/benchmarks"
    "/app/logs/security"
    "/app/logs/xray"
    "/app/logs/integration"
    "/app/logs/metrics"
    "/app/logs/debug"
    "/app/contracts"
)

for dir in "${LOG_DIRS[@]}"; do
    mkdir -p "$dir"
    chmod 777 "$dir"
done

# Enhanced logging function with severity levels and colored output
log_with_timestamp() {
    local message="$1"
    local log_type="${2:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local color_code=""
    local icon=""
    local log_file="$LOG_FILE"

    case $log_type in
        "error")
            color_code=$RED
            icon="❌"
            log_file="$ERROR_LOG"
            ;;
        "security")
            color_code=$PURPLE
            icon="🛡️"
            log_file="$SECURITY_LOG"
            ;;
        "performance")
            color_code=$YELLOW
            icon="⚡"
            log_file="$PERFORMANCE_LOG"
            ;;
        "coverage")
            color_code=$BLUE
            icon="📊"
            log_file="$COVERAGE_LOG"
            ;;
        "xray")
            color_code=$CYAN
            icon="📡"
            log_file="$XRAY_LOG"
            ;;
        "success")
            color_code=$GREEN
            icon="✅"
            ;;
        "warning")
            color_code=$YELLOW
            icon="⚠️"
            ;;
        "integration")
            color_code=$BLUE
            icon="🔄"
            log_file="$INTEGRATION_LOG"
            ;;
        "metrics")
            color_code=$CYAN
            icon="📈"
            log_file="$METRICS_LOG"
            ;;
        "debug")
            color_code=$PURPLE
            icon="🔍"
            log_file="$DEBUG_LOG"
            ;;
        *)
            color_code=$NC
            icon="📝"
            ;;
    esac

    echo -e "${color_code}${timestamp} ${icon} ${message}${NC}" | tee -a "$LOG_FILE" "$log_file"
}

# Enhanced test result handling
handle_test_result() {
    local test_output="$1"
    local test_type="$2"
    local contract_name="$3"
    
    if echo "$test_output" | grep -q "FAILED"; then
        log_with_timestamp "❌ ${test_type} tests failed for ${contract_name}" "error"
        echo "$test_output" >> "$ERROR_LOG"
        return 1
    elif echo "$test_output" | grep -q "PASSED"; then
        log_with_timestamp "✅ ${test_type} tests passed for ${contract_name}" "success"
        return 0
    else
        log_with_timestamp "⚠️ ${test_type} tests had unclear results for ${contract_name}" "warning"
        echo "$test_output" >> "$ERROR_LOG"
        return 2
    fi
}

# Enhanced performance metrics collection
collect_performance_metrics() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "📈 Collecting detailed performance metrics..." "metrics"
    
    # TEAL metrics
    python3 -c "
import sys
sys.path.append('$contracts_dir/src')
from contract import approval_program
from pyteal import *
import json
import time

start_time = time.time()
teal = compileTeal(approval_program(), mode=Mode.Application, version=6)
compile_time = time.time() - start_time

metrics = {
    'teal_size': len(teal.split('\\n')),
    'opcode_count': len([l for l in teal.split('\\n') if l and not l.startswith(('#', '//'))]),
    'compilation_time': compile_time,
    'state_ops': {
        'global_get': teal.count('app_global_get'),
        'local_get': teal.count('app_local_get'),
        'global_put': teal.count('app_global_put'),
        'local_put': teal.count('app_local_put')
    },
    'branching': {
        'if_statements': teal.count('bz') + teal.count('bnz'),
        'switches': teal.count('switch')
    },
    'timestamp': '$(date '+%Y-%m-%d %H:%M:%S')',
    'contract': '$contract_name'
}

with open('/app/logs/metrics/${contract_name}-detailed-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
" 2>/dev/null || log_with_timestamp "⚠️ Failed to collect TEAL metrics" "error"
}

# Comprehensive test suite runner with enhanced error handling
run_comprehensive_tests() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "🔬 Running comprehensive test suite for $contract_name..."
    
    # Setup test environment
    export PYTHONPATH="$contracts_dir/src:$PYTHONPATH"
    
    # Unit Tests with enhanced reporting
    log_with_timestamp "🧪 Running unit tests..." "debug"
    if pytest --cov="$contracts_dir/src" \
             --cov-report=term \
             --cov-report=xml:/app/logs/coverage/${contract_name}-coverage.xml \
             --cov-report=html:/app/logs/coverage/${contract_name}-coverage-html \
             --junitxml=/app/logs/reports/${contract_name}-junit.xml \
             --timeout=30 \
             -v "$contracts_dir/tests/" 2>&1 | tee /app/logs/reports/${contract_name}-unittest.log; then
        log_with_timestamp "✅ Unit tests completed successfully" "success"
    else
        log_with_timestamp "⚠️ Unit tests completed with issues" "warning"
    fi
    
    # Integration Tests with timeout and retry
    log_with_timestamp "🔄 Running integration tests..." "integration"
    for i in {1..3}; do
        if pytest -m integration \
                 --junitxml=/app/logs/reports/${contract_name}-integration.xml \
                 "$contracts_dir/tests/" 2>&1 | tee /app/logs/reports/${contract_name}-integration.log; then
            log_with_timestamp "✅ Integration tests completed successfully" "success"
            break
        else
            log_with_timestamp "⚠️ Integration tests attempt $i failed" "warning"
            [ $i -eq 3 ] && log_with_timestamp "❌ Integration tests failed after 3 attempts" "error"
            sleep 5
        fi
    done
    
    # Performance Tests with metrics
    log_with_timestamp "⚡ Running performance tests..." "performance"
    if pytest -m performance \
             --junitxml=/app/logs/reports/${contract_name}-performance.xml \
             "$contracts_dir/tests/" 2>&1 | tee /app/logs/reports/${contract_name}-performance.log; then
        log_with_timestamp "✅ Performance tests completed successfully" "success"
    else
        log_with_timestamp "⚠️ Performance tests completed with issues" "warning"
    fi
    
    # Collect detailed performance metrics
    collect_performance_metrics "$contract_name" "$contracts_dir"
    
    # Security Analysis with enhanced reporting
    log_with_timestamp "🛡️ Running comprehensive security analysis..." "security"
    
    # Bandit security scan
    bandit -r "$contracts_dir/src/" -f txt -o /app/logs/security/${contract_name}-bandit.log || \
        log_with_timestamp "⚠️ Bandit security scan completed with issues" "warning"
    
    # Static Analysis with detailed reporting
    log_with_timestamp "🔍 Running static analysis..." "debug"
    mypy "$contracts_dir/src/" --strict > /app/logs/security/${contract_name}-mypy.log 2>&1 || \
        log_with_timestamp "⚠️ MyPy type checking completed with issues" "warning"
    
    flake8 "$contracts_dir/src/" > /app/logs/security/${contract_name}-flake8.log 2>&1 || \
        log_with_timestamp "⚠️ Flake8 style checking completed with issues" "warning"
    
    # Code Formatting check
    log_with_timestamp "✨ Checking code formatting..." "debug"
    black "$contracts_dir/src/" --check > /app/logs/security/${contract_name}-black.log 2>&1 || \
        log_with_timestamp "⚠️ Black formatting check completed with issues" "warning"
    
    # TEAL Analysis with enhanced error handling
    log_with_timestamp "📝 Analyzing TEAL output..." "debug"
    if ! python3 -c "
from pyteal import *
import sys
sys.path.append('$contracts_dir/src')
from contract import approval_program
teal = compileTeal(approval_program(), mode=Mode.Application, version=6)
print(teal)" > /app/logs/${contract_name}-teal.log 2>&1; then
        log_with_timestamp "❌ TEAL compilation failed" "error"
    fi
}

# Main execution with enhanced watch/polling logic
watch_dir="/app/input"
MARKER_DIR="/app/.processed"
mkdir -p "$watch_dir" "$MARKER_DIR"

log_with_timestamp "🚀 Starting Enhanced Algorand Container v2.0..."
log_with_timestamp "📡 Watching for PyTeal smart contract files in $watch_dir..."
log_with_timestamp "👤 Current User: AduAkorful"
log_with_timestamp "🕒 Start Time: 2025-07-24 17:29:29 UTC"

process_contract() {
    local file="$1"
    local filename=$(basename "$file")
    local MARKER_FILE="$MARKER_DIR/$filename.processed"
    local CURRENT_HASH=$(sha256sum "$file" | awk '{print $1}')
    
    # Check for duplicate processing
    if [ -f "$MARKER_FILE" ]; then
        local LAST_HASH=$(cat "$MARKER_FILE")
        if [ "$CURRENT_HASH" == "$LAST_HASH" ]; then
            log_with_timestamp "⏭️ Skipping duplicate processing of $filename (same content hash)" "debug"
            return 0
        fi
    fi
    
    # Update marker file
    echo "$CURRENT_HASH" > "$MARKER_FILE"
    
    # Process the contract
    {
        start_time=$(date +%s)
        CONTRACT_NAME="${filename%.py}"
        CONTRACTS_DIR="/app/contracts/${CONTRACT_NAME}"
        
        log_with_timestamp "🔨 Setting up contract directory structure..." "debug"
        mkdir -p "$CONTRACTS_DIR/src" "$CONTRACTS_DIR/tests"
        
        # Copy contract and test files
        cp "$file" "$CONTRACTS_DIR/src/contract.py"
        if [ ! -f "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py" ]; then
            cp /app/tests/test_contract_suite.py "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py" 2>/dev/null || \
                log_with_timestamp "⚠️ Failed to copy test suite template" "warning"
            log_with_timestamp "🧪 Copied comprehensive test suite for $CONTRACT_NAME" "success"
        fi
        
        # Run tests and analysis
        run_comprehensive_tests "$CONTRACT_NAME" "$CONTRACTS_DIR"
        
        # Generate report
        if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
            log_with_timestamp "📊 Generating comprehensive report..." "debug"
            if node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME" 2>/dev/null; then
                log_with_timestamp "✅ Report generated: /app/logs/reports/${CONTRACT_NAME}-report.md" "success"
            else
                log_with_timestamp "❌ Failed to generate report" "error"
            fi
        fi
        
        # Calculate and log execution time
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_with_timestamp "🏁 Completed processing $filename (duration: ${duration}s)" "success"
        log_with_timestamp "===========================================" "debug"
        
        # Record metrics
        echo "{
            \"contract\": \"$CONTRACT_NAME\",
            \"timestamp\": \"$(date -u '+%Y-%m-%d %H:%M:%S')\",
            \"duration\": $duration,
            \"status\": \"completed\"
        }" > "/app/logs/metrics/${CONTRACT_NAME}-execution-metrics.json"
        
    } 2>&1 | tee -a "/app/logs/debug/${CONTRACT_NAME}-processing.log"
}

# Primary monitoring using inotifywait
if ! inotifywait -m -e close_write,moved_to,create "$watch_dir" 2>/dev/null |
    while read -r directory events filename; do
        if [[ "$filename" =~ \.py$ ]]; then
            FILE_PATH="$watch_dir/$filename"
            [ ! -f "$FILE_PATH" ] && continue
            
            log_with_timestamp "📥 Detected new/modified file: $filename" "debug"
            process_contract "$FILE_PATH"
        fi
    done
then
    # Fallback polling mechanism
    log_with_timestamp "❌ inotifywait failed, switching to fallback polling mechanism" "warning"
    
    while true; do
        for file in "$watch_dir"/*.py; do
            [ ! -f "$file" ] && continue
            
            log_with_timestamp "🔍 Polling detected file: $(basename "$file")" "debug"
            process_contract "$file"
        done
        
        # Record health check
        echo "{
            \"timestamp\": \"$(date -u '+%Y-%m-%d %H:%M:%S')\",
            \"status\": \"polling\",
            \"last_check\": \"$(date -u '+%Y-%m-%d %H:%M:%S')\"
        }" > "/app/logs/metrics/container-health.json"
        
        sleep 5
    done
fi

# Error handling for script termination
cleanup() {
    log_with_timestamp "🛑 Container stopping... Recording final state" "warning"
    echo "{
        \"timestamp\": \"$(date -u '+%Y-%m-%d %H:%M:%S')\",
        \"status\": \"stopped\",
        \"user\": \"AduAkorful\"
    }" > "/app/logs/metrics/container-final-state.json"
}

trap cleanup EXIT
