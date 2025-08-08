#!/bin/bash
set -e

echo "🚀 Starting Enhanced Algorand PyTeal Container..."

# Verify essential tools are available
echo "🔧 Verifying tool availability..."
command -v python3 >/dev/null 2>&1 && echo "✅ Python3 available" || echo "⚠️ Python3 not found"
command -v pytest >/dev/null 2>&1 && echo "✅ PyTest available" || echo "⚠️ PyTest not found"
command -v bandit >/dev/null 2>&1 && echo "✅ Bandit available" || echo "⚠️ Bandit not found"
command -v mypy >/dev/null 2>&1 && echo "✅ MyPy available" || echo "⚠️ MyPy not found"
command -v flake8 >/dev/null 2>&1 && echo "✅ Flake8 available" || echo "⚠️ Flake8 not found"
command -v black >/dev/null 2>&1 && echo "✅ Black available" || echo "⚠️ Black not found"
python3 -c "import pyteal; print('✅ PyTeal available')" 2>/dev/null || echo "⚠️ PyTeal not found"
command -v node >/dev/null 2>&1 && echo "✅ Node.js available" || echo "⚠️ Node.js not found"

# Enhanced logging setup with color support
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test template location
TEST_TEMPLATE="/app/scripts/test_template.py"

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
    local timestamp="[$(date '+%Y-%m-24 %H:%M:%S')]"
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
    
    # TEAL metrics with enhanced error handling
    python3 -c "
import sys
sys.path.append('$contracts_dir/src')
try:
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

    # Additional analysis for contract complexity
    metrics['complexity'] = {
        'scratch_vars': len([l for l in teal.split('\\n') if 'store' in l.lower()]),
        'inner_transactions': teal.count('itxn_begin'),
        'asset_operations': sum(teal.count(op) for op in ['asset_holding_get', 'asset_params_get']),
        'box_operations': sum(teal.count(op) for op in ['box_get', 'box_put', 'box_del']),
    }

    # Check for potential optimizations
    metrics['optimization_hints'] = []
    if metrics['opcode_count'] > 400:
        metrics['optimization_hints'].append('High opcode count - consider splitting logic')
    if metrics['state_ops']['global_get'] + metrics['state_ops']['local_get'] > 15:
        metrics['optimization_hints'].append('High number of state reads - consider caching')

    with open('/app/logs/metrics/${contract_name}-detailed-metrics.json', 'w') as f:
        json.dump(metrics, f, indent=2)
except Exception as e:
    error_data = {
        'error': str(e),
        'timestamp': '$(date '+%Y-%m-%d %H:%M:%S')',
        'contract': '$contract_name'
    }
    with open('/app/logs/metrics/${contract_name}-error-metrics.json', 'w') as f:
        json.dump(error_data, f, indent=2)
    sys.exit(1)
" 2>/dev/null || {
        log_with_timestamp "⚠️ Failed to collect TEAL metrics" "error"
        echo "{
            \"error\": \"TEAL metrics collection failed\",
            \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\",
            \"contract\": \"$contract_name\"
        }" > "/app/logs/metrics/${contract_name}-error-metrics.json"
    }

    # Additional performance metrics
    {
        # Memory usage analysis
        local mem_usage=$(ps -o rss= -p $$)
        
        # Execution time tracking
        local exec_metrics="{
            \"memory_usage_kb\": $mem_usage,
            \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\",
            \"contract\": \"$contract_name\"
        }"
        echo "$exec_metrics" > "/app/logs/metrics/${contract_name}-execution-metrics.json"
        
        # Record system metrics
        local sys_metrics="{
            \"cpu_usage\": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'),
            \"memory_total\": $(free -m | awk '/Mem:/ {print $2}'),
            \"memory_used\": $(free -m | awk '/Mem:/ {print $3}'),
            \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\",
            \"contract\": \"$contract_name\"
        }"
        echo "$sys_metrics" > "/app/logs/metrics/${contract_name}-system-metrics.json"
    } 2>/dev/null || log_with_timestamp "⚠️ Failed to collect system metrics" "warning"
}

# Comprehensive test suite runner with enhanced error handling
run_comprehensive_tests() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "🔬 Running comprehensive test suite for $contract_name..."
    
    # Setup test environment - CLEAR ALL PYTHON CACHES
    rm -rf ~/.cache/pip __pycache__ .pytest_cache 2>/dev/null || true
    find "$contracts_dir" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$contracts_dir" -name "*.pyc" -delete 2>/dev/null || true
    export PYTHONDONTWRITEBYTECODE=1
    export PYTHONPATH="$contracts_dir/src:$PYTHONPATH"
    export CONTRACT_NAME="$contract_name"
    
    # Create test result directory
    local test_results_dir="/app/logs/reports/${contract_name}"
    mkdir -p "$test_results_dir"
    
    # Unit Tests with enhanced reporting
    log_with_timestamp "🧪 Running unit tests..." "debug"
    cd "$contracts_dir"
    if python -m pytest --cov="src" \
             --cov-report=term \
             --cov-report=xml:"$test_results_dir/coverage.xml" \
             --cov-report=html:"$test_results_dir/coverage-html" \
             --junitxml="$test_results_dir/junit.xml" \
             --timeout=30 \
             --tb=short \
             -v tests/ 2>&1 | tee "$test_results_dir/unittest.log"; then
        log_with_timestamp "✅ Unit tests completed successfully" "success"
    else
        log_with_timestamp "⚠️ Unit tests completed with issues (exit code: $?)" "warning"
        # Still capture some output even if tests fail
        echo "Test execution attempted but failed" >> "$test_results_dir/unittest.log"
    fi
    cd /app
    
    # Integration Tests with timeout and retry
    log_with_timestamp "🔄 Running integration tests..." "integration"
    cd "$contracts_dir"
    CONTRACT_NAME="$contract_name" python -m pytest -m integration \
             --junitxml="$test_results_dir/integration.xml" \
             --tb=short \
             tests/ 2>&1 | tee "$test_results_dir/integration.log" || \
        log_with_timestamp "⚠️ Integration tests completed with issues" "warning"
    cd /app
    
    # Performance Tests with metrics
    log_with_timestamp "⚡ Running performance tests..." "performance"
    cd "$contracts_dir"
    CONTRACT_NAME="$contract_name" python -m pytest -m performance \
             --junitxml="$test_results_dir/performance.xml" \
             --tb=short \
             tests/ 2>&1 | tee "$test_results_dir/performance.log" || \
        log_with_timestamp "⚠️ Performance tests completed with issues" "warning"
    cd /app
    
    # Collect detailed performance metrics
    collect_performance_metrics "$contract_name" "$contracts_dir"
    
    # Security Analysis with enhanced reporting
    log_with_timestamp "🛡️ Running comprehensive security analysis..." "security"
    
    # Bandit security scan with configuration
    log_with_timestamp "🔍 Running Bandit security scan..." "security"
    if bandit -r "$contracts_dir/src/" \
           -f txt \
           -o "$test_results_dir/bandit.log" \
           --confidence-level low \
           --severity-level low 2>&1; then
        log_with_timestamp "✅ Bandit scan completed" "success"
    else
        log_with_timestamp "⚠️ Bandit security scan completed with issues" "warning"
        # Ensure we have some output even if bandit fails
        echo "Bandit scan attempted but failed or found issues" >> "$test_results_dir/bandit.log"
    fi
    
    # Static Analysis with detailed reporting
    log_with_timestamp "🔍 Running static analysis..." "debug"
    
    # MyPy type checking with strict mode
    log_with_timestamp "🔍 Running MyPy type checking..." "debug"
    if mypy "$contracts_dir/src/" \
         --show-error-codes \
         --show-error-context \
         --pretty \
         --ignore-missing-imports \
         > "$test_results_dir/mypy.log" 2>&1; then
        log_with_timestamp "✅ MyPy type checking completed" "success"
    else
        log_with_timestamp "⚠️ MyPy type checking completed with issues" "warning"
        echo "MyPy analysis attempted" >> "$test_results_dir/mypy.log"
    fi
    
    # Flake8 style checking with detailed configuration
    log_with_timestamp "🔍 Running Flake8 style checking..." "debug"
    if flake8 "$contracts_dir/src/" \
           --max-line-length=88 \
           --extend-ignore=E203 \
           --statistics \
           --show-source \
           > "$test_results_dir/flake8.log" 2>&1; then
        log_with_timestamp "✅ Flake8 style checking completed" "success"
    else
        log_with_timestamp "⚠️ Flake8 style checking completed with issues" "warning"
        echo "Flake8 analysis attempted" >> "$test_results_dir/flake8.log"
    fi
    
    # Code Formatting check with Black
    log_with_timestamp "✨ Checking code formatting..." "debug"
    if black "$contracts_dir/src/" \
          --check \
          --diff \
          > "$test_results_dir/black.log" 2>&1; then
        log_with_timestamp "✅ Black formatting check completed" "success"
    else
        log_with_timestamp "⚠️ Black formatting check completed with issues" "warning"
        echo "Black formatting check attempted" >> "$test_results_dir/black.log"
    fi
    
    # TEAL Analysis with enhanced error handling
    log_with_timestamp "📝 Analyzing TEAL output..." "debug"
    cd "$contracts_dir"
    if python3 -c "
import sys
sys.path.append('src')
try:
    import contract
    from pyteal import compileTeal, Mode
    
    # Try to compile approval program
    if hasattr(contract, 'approval_program'):
        approval_teal = compileTeal(contract.approval_program(), mode=Mode.Application, version=6)
        print('=== APPROVAL PROGRAM ===')
        print(approval_teal)
        
        # Count opcodes for performance metrics
        opcodes = len([line for line in approval_teal.split('\n') if line and not line.startswith(('#', '//'))])
        print(f'\n=== METRICS ===')
        print(f'Approval Program Opcodes: {opcodes}')
    
    # Try to compile clear state program
    if hasattr(contract, 'clear_state_program'):
        clear_teal = compileTeal(contract.clear_state_program(), mode=Mode.Application, version=6)
        print('\n=== CLEAR STATE PROGRAM ===')
        print(clear_teal)
    
    print('\n=== COMPILATION SUCCESS ===')
    
except ImportError as e:
    print(f'Import Error: {str(e)}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Compilation Error: {str(e)}', file=sys.stderr)
    sys.exit(1)
" > "$test_results_dir/teal.log" 2> "$test_results_dir/teal-error.log"; then
        log_with_timestamp "✅ TEAL compilation successful" "success"
    else
        log_with_timestamp "❌ TEAL compilation failed" "error"
        cat "$test_results_dir/teal-error.log" >> "$ERROR_LOG"
        echo "TEAL compilation failed" >> "$test_results_dir/teal.log"
    fi
    cd /app
    
    # Generate test summary
    {
        echo "Test Summary for $contract_name"
        echo "================================"
        echo "Timestamp: $(date '+%Y-%m-24 %H:%M:%S')"
        echo "Unit Tests: $(grep "failed\|passed" "$test_results_dir/unittest.log" | tail -n1)"
        echo "Integration Tests: $(grep "failed\|passed" "$test_results_dir/integration.log" | tail -n1)"
        echo "Performance Tests: $(grep "failed\|passed" "$test_results_dir/performance.log" | tail -n1)"
        echo "Security Issues: $(grep "Issues Identified" "$test_results_dir/bandit.log" | tail -n1)"
        echo "Type Issues: $(grep "Found" "$test_results_dir/mypy.log" | tail -n1)"
        echo "Style Issues: $(grep "summary" "$test_results_dir/flake8.log" | tail -n1)"
    } > "$test_results_dir/summary.txt"
}

# Main execution with enhanced watch/polling logic
watch_dir="/app/input"
MARKER_DIR="/app/.processed"
mkdir -p "$watch_dir" "$MARKER_DIR"

# GLOBAL CACHE CLEANUP AT STARTUP
rm -rf ~/.cache/pip ~/.cache/pytest __pycache__ .pytest_cache 2>/dev/null || true
find /app -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find /app -name "*.pyc" -delete 2>/dev/null || true
export PYTHONDONTWRITEBYTECODE=1

log_with_timestamp "🚀 Starting Enhanced Algorand Container v2.0..."
log_with_timestamp "📡 Watching for PyTeal smart contract files in $watch_dir..."
log_with_timestamp "👤 Current User: AduAkorful"
log_with_timestamp "🕒 Start Time: 2025-07-24 19:41:24 UTC"
log_with_timestamp "🧹 All Python caches cleared for fresh analysis"

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
        
        # CLEAR ALL PYTHON CACHES BEFORE PROCESSING
        rm -rf ~/.cache/pip __pycache__ .pytest_cache 2>/dev/null || true
        find /app -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
        find /app -name "*.pyc" -delete 2>/dev/null || true
        export PYTHONDONTWRITEBYTECODE=1
        
        # Copy contract and create necessary files
        cp "$file" "$CONTRACTS_DIR/src/contract.py"
        touch "$CONTRACTS_DIR/src/__init__.py"
        touch "$CONTRACTS_DIR/tests/__init__.py"
        
        # Copy dynamic test template
        if [ -f "$TEST_TEMPLATE" ]; then
            cp "$TEST_TEMPLATE" "$CONTRACTS_DIR/tests/test_contract.py"
            log_with_timestamp "🧪 Copied dynamic test template for $CONTRACT_NAME" "success"
        else
            log_with_timestamp "⚠️ Test template not found at $TEST_TEMPLATE" "error"
            return 1
        fi
        
        # Export contract name for test environment
        export CONTRACT_NAME
        
        # Run tests and analysis
        run_comprehensive_tests "$CONTRACT_NAME" "$CONTRACTS_DIR"
        
        # Generate report
        if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
            log_with_timestamp "📊 Generating comprehensive report..." "debug"
            if node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME" 2>/dev/null; then
                log_with_timestamp "✅ Report generated: /app/logs/reports/${CONTRACT_NAME}-report.txt" "success"
            else
                log_with_timestamp "❌ Failed to generate report" "error"
            fi
        fi
        
        # Calculate and log execution time
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_with_timestamp "🏁 Completed processing $filename (duration: ${duration}s)" "success"
        log_with_timestamp "===========================================" "debug"
        
        # Record detailed execution metrics
        echo "{
            \"contract\": \"$CONTRACT_NAME\",
            \"timestamp\": \"$(date -u '+%Y-%m-%d %H:%M:%S')\",
            \"duration\": $duration,
            \"status\": \"completed\",
            \"test_summary\": {
                \"unit_tests\": $(grep -c "PASSED" "/app/logs/reports/${CONTRACT_NAME}/unittest.log" || echo 0),
                \"integration_tests\": $(grep -c "PASSED" "/app/logs/reports/${CONTRACT_NAME}/integration.log" || echo 0),
                \"performance_tests\": $(grep -c "PASSED" "/app/logs/reports/${CONTRACT_NAME}/performance.log" || echo 0)
            },
            \"system_metrics\": {
                \"cpu_usage\": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'),
                \"memory_used\": $(free -m | awk '/Mem:/ {print $3}'),
                \"disk_usage\": $(df -h /app | awk 'NR==2 {print $5}' | sed 's/%//')
            }
        }" > "/app/logs/metrics/${CONTRACT_NAME}-execution-metrics.json"
        
    } 2>&1 | tee -a "/app/logs/debug/${CONTRACT_NAME}-processing.log"
}

# Primary monitoring using inotifywait with enhanced error handling
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
    # Fallback polling mechanism with enhanced monitoring
    log_with_timestamp "❌ inotifywait failed, switching to fallback polling mechanism" "warning"
    
    while true; do
        for file in "$watch_dir"/*.py; do
            [ ! -f "$file" ] && continue
            
            log_with_timestamp "🔍 Polling detected file: $(basename "$file")" "debug"
            process_contract "$file"
        done
        
        # Record health check with enhanced metrics
        echo "{
            \"timestamp\": \"$(date -u '+%Y-%m-%d %H:%M:%S')\",
            \"status\": \"polling\",
            \"last_check\": \"$(date -u '+%Y-%m-%d %H:%M:%S')\",
            \"system_health\": {
                \"cpu_usage\": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'),
                \"memory_used\": $(free -m | awk '/Mem:/ {print $3}'),
                \"disk_usage\": $(df -h /app | awk 'NR==2 {print $5}' | sed 's/%//'),
                \"process_count\": $(ps aux | grep -c "[p]ython")
            }
        }" > "/app/logs/metrics/container-health.json"
        
        sleep 5
    done
fi

# Error handling for specific signals
handle_signal() {
    local signal=$1
    local pid=$2
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S')
    
    log_with_timestamp "⚠️ Received signal $signal" "warning"
    
    echo "{
        \"timestamp\": \"$timestamp\",
        \"signal\": \"$signal\",
        \"pid\": $pid,
        \"status\": \"interrupted\",
        \"user\": \"AduAkorful\"
    }" > "/app/logs/metrics/interrupt-state.json"
    
    cleanup
    exit 1
}

# Enhanced cleanup function
cleanup() {
    local exit_code=$?
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S')
    
    log_with_timestamp "🛑 Container stopping... Recording final state" "warning"
    
    # Save processing state
    for marker in "$MARKER_DIR"/*.processed; do
        if [ -f "$marker" ]; then
            contract_name=$(basename "$marker" .py.processed)
            if [ -d "/app/contracts/$contract_name" ]; then
                # Archive contract state
                tar -czf "/app/logs/archive/${contract_name}-$(date +%s).tar.gz" \
                    -C "/app/contracts" "$contract_name" 2>/dev/null || true
            fi
        fi
    done
    
    # Generate final metrics
    echo "{
        \"timestamp\": \"$timestamp\",
        \"status\": \"stopped\",
        \"exit_code\": $exit_code,
        \"user\": \"AduAkorful\",
        \"uptime\": $SECONDS,
        \"processed_contracts\": $(find "$MARKER_DIR" -type f | wc -l),
        \"system_state\": {
            \"cpu_usage\": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'),
            \"memory_used\": $(free -m | awk '/Mem:/ {print $3}'),
            \"disk_usage\": $(df -h /app | awk 'NR==2 {print $5}' | sed 's/%//'),
            \"process_count\": $(ps aux | grep -c "[p]ython")
        },
        \"error_summary\": {
            \"total_errors\": $(grep -c "ERROR" "$ERROR_LOG" 2>/dev/null || echo 0),
            \"last_error\": \"$(tail -n 1 "$ERROR_LOG" 2>/dev/null || echo 'None')\"
        }
    }" > "/app/logs/metrics/container-final-state.json"
    
    # Generate final report
    {
        echo "Container Execution Summary"
        echo "=========================="
        echo "Start Time: 2025-07-24 19:42:22 UTC"
        echo "End Time: $timestamp"
        echo "User: AduAkorful"
        echo "Exit Code: $exit_code"
        echo "Total Runtime: $SECONDS seconds"
        echo ""
        echo "Processed Contracts:"
        find "$MARKER_DIR" -type f -exec basename {} .processed \;
        echo ""
        echo "Error Summary:"
        tail -n 10 "$ERROR_LOG" 2>/dev/null || echo "No errors recorded"
    } > "/app/logs/reports/final-execution-report.txt"
    
    # Compress logs
    log_with_timestamp "📦 Archiving logs..." "debug"
    tar -czf "/app/logs/archive/logs-$(date +%s).tar.gz" \
        -C "/app/logs" \
        --exclude="archive" \
        . 2>/dev/null || true
    
    log_with_timestamp "👋 Container stopped. Final reports available in /app/logs/reports" "success"
}

# Set up signal handlers
trap 'handle_signal SIGTERM $$' SIGTERM
trap 'handle_signal SIGINT $$' SIGINT
trap 'handle_signal SIGHUP $$' SIGHUP
trap cleanup EXIT

# Create archive directory
mkdir -p "/app/logs/archive"
chmod 777 "/app/logs/archive"

# Record container start state
echo "{
    \"timestamp\": \"2025-07-24 19:42:22\",
    \"status\": \"started\",
    \"user\": \"AduAkorful\",
    \"system_state\": {
        \"cpu_usage\": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'),
        \"memory_used\": $(free -m | awk '/Mem:/ {print $3}'),
        \"disk_usage\": $(df -h /app | awk 'NR==2 {print $5}' | sed 's/%//'),
        \"process_count\": $(ps aux | grep -c "[p]ython")
    }
}" > "/app/logs/metrics/container-start-state.json"
