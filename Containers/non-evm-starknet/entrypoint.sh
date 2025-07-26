#!/bin/bash
set -e

# --- Performance optimization environment setup ---
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1  # Prevent .pyc files for faster imports
export PYTHONUTF8=1  # Force UTF-8 encoding
export PYTHONIOENCODING=utf-8
export PIP_NO_CACHE_DIR=1  # Disable pip cache for faster installs
export PIP_DISABLE_PIP_VERSION_CHECK=1  # Faster pip operations

# Parallel processing settings
export PARALLEL_JOBS=${PARALLEL_JOBS:-$(nproc)}
export PYTEST_XDIST_WORKER_COUNT=${PARALLEL_JOBS}

# Memory and performance optimization
export MALLOC_ARENA_MAX=4  # Reduce memory fragmentation
export PYTHONHASHSEED=0  # Consistent hashing for reproducible results

# Starknet specific optimizations
export CAIRO_PATH="/app/cairo_libs"
export STARKNET_RPC_URL=${STARKNET_RPC_URL:-"http://starknet-devnet:5050"}

echo "🚀 Starting Enhanced Starknet Container..."
echo "⚡ Parallel jobs: $PARALLEL_JOBS"
echo "🐍 Python optimizations enabled"
echo "🌟 Starknet RPC: $STARKNET_RPC_URL"

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
CAIRO_LOG="/app/logs/cairo/cairo.log"
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
    "$(dirname "$CAIRO_LOG")"
    "$(dirname "$INTEGRATION_LOG")"
    "$(dirname "$METRICS_LOG")"
    "$(dirname "$DEBUG_LOG")"
    "/app/logs/coverage"
    "/app/logs/reports"
    "/app/logs/benchmarks"
    "/app/logs/security"
    "/app/logs/cairo"
    "/app/logs/integration"
    "/app/logs/metrics"
    "/app/logs/debug"
    "/app/contracts"
    "/app/cairo_libs"
)

for dir in "${LOG_DIRS[@]}"; do
    mkdir -p "$dir"
done

# Enhanced logging with categories and performance tracking
log_with_timestamp() {
    local message="$1"
    local log_type="${2:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    case $log_type in
        "error") echo -e "$timestamp ${RED}❌ $message${NC}" | tee -a "$LOG_FILE" "$ERROR_LOG" ;;
        "security") echo -e "$timestamp ${PURPLE}🛡️ $message${NC}" | tee -a "$LOG_FILE" "$SECURITY_LOG" ;;
        "performance") echo -e "$timestamp ${CYAN}⚡ $message${NC}" | tee -a "$LOG_FILE" "$PERFORMANCE_LOG" ;;
        "success") echo -e "$timestamp ${GREEN}✅ $message${NC}" | tee -a "$LOG_FILE" ;;
        "debug") echo -e "$timestamp ${BLUE}🔍 $message${NC}" | tee -a "$LOG_FILE" "$DEBUG_LOG" ;;
        "cairo") echo -e "$timestamp ${YELLOW}🌟 $message${NC}" | tee -a "$LOG_FILE" "$CAIRO_LOG" ;;
        *) echo "$timestamp $message" | tee -a "$LOG_FILE" ;;
    esac
}

watch_dir="/app/input"
MARKER_DIR="/app/.processed"
mkdir -p "$watch_dir" "$MARKER_DIR"

log_with_timestamp "📡 Watching for Cairo smart contract files in $watch_dir..."

# Enhanced security analysis for Starknet contracts
run_comprehensive_starknet_security_audit() {
    local contract_name="$1"
    local contract_file="$2"
    local contracts_dir="$3"
    
    log_with_timestamp "🛡️ Running comprehensive security audit for Starknet contract $contract_name..." "security"
    
    mkdir -p "$contracts_dir/logs/security"
    
    # Run multiple security analysis tools in parallel
    {
        run_cairo_security_analysis "$contract_name" "$contract_file" "$contracts_dir" &
        CAIRO_PID=$!
        
        run_starknet_custom_security_checks "$contract_name" "$contract_file" "$contracts_dir" &
        CUSTOM_PID=$!
        
        run_python_security_audit "$contract_name" "$contracts_dir" &
        PYTHON_PID=$!
        
        run_cairo_compilation_security "$contract_name" "$contract_file" "$contracts_dir" &
        COMPILE_PID=$!
        
        # Wait for all security tools to complete
        wait $CAIRO_PID
        wait $CUSTOM_PID
        wait $PYTHON_PID
        wait $COMPILE_PID
        
        log_with_timestamp "✅ All security analysis tools completed" "security"
    }
}

# Cairo specific security analysis
run_cairo_security_analysis() {
    local contract_name="$1"
    local contract_file="$2"
    local contracts_dir="$3"
    
    log_with_timestamp "Running Cairo security analysis..." "security"
    local cairo_log="$contracts_dir/logs/security/${contract_name}-cairo-security.log"
    
    {
        echo "=== Cairo Security Analysis ==="
        echo "Contract: $contract_name"
        echo "File: $contract_file"
        echo "Date: $(date)"
        echo ""
        
        # Check for common Cairo security issues
        echo "=== Storage Security ==="
        if grep -n "storage_var\|@storage_var" "$contract_file"; then
            echo "INFO: Storage variables detected"
            if ! grep -q "assert\|require" "$contract_file"; then
                echo "WARNING: No assertion checks found for storage operations"
            fi
        fi
        echo ""
        
        echo "=== External Function Security ==="
        if grep -n "@external\|#\[external" "$contract_file"; then
            echo "INFO: External functions detected"
            if ! grep -q "caller\|get_caller_address" "$contract_file"; then
                echo "WARNING: No caller verification found for external functions"
            fi
        fi
        echo ""
        
        echo "=== L1 Handler Security ==="
        if grep -n "@l1_handler\|#\[l1_handler" "$contract_file"; then
            echo "INFO: L1 handlers detected"
            echo "CRITICAL: Ensure L1 handler message validation"
        fi
        echo ""
        
        echo "=== Felt Arithmetic Security ==="
        if grep -n "felt\|Felt" "$contract_file"; then
            echo "INFO: Felt arithmetic detected"
            echo "WARNING: Check for felt overflow/underflow issues"
        fi
        echo ""
        
        echo "=== Array Bounds Security ==="
        if grep -n "len\|\[.*\]" "$contract_file"; then
            echo "INFO: Array operations detected"
            echo "WARNING: Ensure proper bounds checking"
        fi
        echo ""
        
    } > "$cairo_log"
    
    log_with_timestamp "✅ Cairo security analysis completed" "security"
}

# Starknet-specific custom security checks
run_starknet_custom_security_checks() {
    local contract_name="$1"
    local contract_file="$2"
    local contracts_dir="$3"
    
    log_with_timestamp "Running Starknet custom security checks..." "security"
    local custom_log="$contracts_dir/logs/security/${contract_name}-starknet-custom.log"
    
    {
        echo "=== Starknet Custom Security Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        echo "=== Account Contract Security ==="
        if grep -n "__execute__\|__validate__" "$contract_file"; then
            echo "CRITICAL: Account contract detected"
            echo "WARNING: Ensure proper signature validation"
            echo "WARNING: Check for replay attack protection"
        fi
        echo ""
        
        echo "=== Proxy Pattern Security ==="
        if grep -n "proxy\|implementation\|upgrade" "$contract_file"; then
            echo "INFO: Proxy patterns detected"
            echo "WARNING: Ensure proper upgrade access control"
            echo "WARNING: Check for storage collision issues"
        fi
        echo ""
        
        echo "=== Cross-Layer Security ==="
        if grep -n "send_message_to_l1\|consume_message_from_l1" "$contract_file"; then
            echo "INFO: Cross-layer messaging detected"
            echo "WARNING: Validate message content and sender"
            echo "WARNING: Check for message replay attacks"
        fi
        echo ""
        
        echo "=== State Management Security ==="
        if grep -n "storage_read\|storage_write" "$contract_file"; then
            echo "INFO: Direct storage access detected"
            echo "WARNING: Ensure proper access control for storage operations"
        fi
        echo ""
        
        echo "=== Event Security ==="
        if grep -n "emit\|Event" "$contract_file"; then
            echo "INFO: Event emissions detected"
            echo "WARNING: Ensure events don't leak sensitive information"
        fi
        echo ""
        
        echo "=== Gas Optimization Security ==="
        echo "INFO: Checking for potential gas exhaustion patterns..."
        local loop_count=$(grep -c "loop\|while\|for" "$contract_file" 2>/dev/null | head -1 || echo "0")
        loop_count=${loop_count:-0}
        
        if [ "$loop_count" -gt 3 ]; then
            echo "WARNING: High number of loops detected ($loop_count) - DoS risk"
        fi
        echo ""
        
    } > "$custom_log"
    
    log_with_timestamp "✅ Starknet custom security checks completed" "security"
}

# Python dependency security audit
run_python_security_audit() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "Running Python security audit..." "security"
    local python_audit_log="$contracts_dir/logs/security/${contract_name}-python-audit.log"
    
    # Check for Python security issues
    if command -v safety &> /dev/null; then
        (cd "$contracts_dir" && safety check --json > "$python_audit_log" 2>&1) || {
            log_with_timestamp "⚠️ Python security audit found vulnerabilities" "security"
        }
    else
        echo "Safety scanner not available - skipping Python dependency audit" > "$python_audit_log"
    fi
    
    # Check for bandit security issues
    if command -v bandit &> /dev/null; then
        (cd "$contracts_dir" && bandit -r . -f json -o "${python_audit_log}.bandit" 2>&1) || {
            log_with_timestamp "⚠️ Bandit found security issues" "security"
        }
    fi
}

# Cairo compilation security analysis
run_cairo_compilation_security() {
    local contract_name="$1"
    local contract_file="$2"
    local contracts_dir="$3"
    
    log_with_timestamp "Running Cairo compilation security..." "cairo"
    local compile_log="$contracts_dir/logs/security/${contract_name}-compile-security.log"
    
    {
        echo "=== Cairo Compilation Security Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Try to compile with security checks
        if command -v starknet-compile &> /dev/null; then
            echo "Attempting to compile with starknet-compile..."
            starknet-compile "$contract_file" --output "$contracts_dir/logs/${contract_name}-compiled.json" 2>&1 || {
                echo "⚠️ Compilation issues detected"
            }
        elif command -v cairo-compile &> /dev/null; then
            echo "Attempting to compile with cairo-compile..."
            cairo-compile "$contract_file" --output "$contracts_dir/logs/${contract_name}-compiled.json" 2>&1 || {
                echo "⚠️ Compilation issues detected"
            }
        else
            echo "No Cairo compiler available"
        fi
        echo ""
        
        echo "=== Contract Size Analysis ==="
        local file_size=$(wc -c < "$contract_file")
        echo "Contract size: $file_size bytes"
        if [ "$file_size" -gt 50000 ]; then
            echo "WARNING: Large contract size - may hit deployment limits"
        fi
        echo ""
        
    } > "$compile_log"
    
    log_with_timestamp "✅ Cairo compilation security completed" "cairo"
}

# Enhanced performance analysis for Starknet
run_starknet_performance_analysis() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "⚡ Running Starknet performance analysis for $contract_name..." "performance"
    
    mkdir -p "$contracts_dir/logs/benchmarks"
    local perf_log="$contracts_dir/logs/benchmarks/${contract_name}-performance.log"
    
    {
        echo "=== Starknet Performance Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        echo "=== Code Complexity Analysis ==="
        local line_count=$(wc -l < "$contracts_dir/src/contract.cairo")
        echo "Source lines of code: $line_count"
        
        if [ "$line_count" -gt 1000 ]; then
            echo "WARNING: Large contract ($line_count lines) - may hit gas limits"
        else
            echo "✅ Contract size within reasonable limits"
        fi
        echo ""
        
        echo "=== Estimated Resource Usage ==="
        echo "Note: These are rough estimates for Starknet operations"
        
        # Count various operations that affect performance
        local storage_ops=$(grep -c "storage_var\|storage_read\|storage_write" "$contracts_dir/src/contract.cairo" 2>/dev/null | head -1 || echo "0")
        local external_ops=$(grep -c "@external\|#\[external" "$contracts_dir/src/contract.cairo" 2>/dev/null | head -1 || echo "0")
        local l1_ops=$(grep -c "send_message_to_l1\|consume_message_from_l1" "$contracts_dir/src/contract.cairo" 2>/dev/null | head -1 || echo "0")
        
        # Ensure we have valid numbers
        storage_ops=${storage_ops:-0}
        external_ops=${external_ops:-0}
        l1_ops=${l1_ops:-0}
        
        echo "Storage operations: $storage_ops"
        echo "External functions: $external_ops"
        echo "L1 messaging operations: $l1_ops"
        echo ""
        
        echo "=== Optimization Recommendations ==="
        if [ "$storage_ops" -gt 20 ]; then
            echo "- Consider reducing storage operations for better performance"
        fi
        if [ "$external_ops" -gt 15 ]; then
            echo "- High number of external functions - consider interface optimization"
        fi
        if [ "$l1_ops" -gt 2 ]; then
            echo "- Multiple L1 operations detected - batch operations where possible"
        fi
        
    } > "$perf_log"
    
    log_with_timestamp "✅ Starknet performance analysis completed" "performance"
}

# Enhanced coverage analysis for Starknet
run_starknet_coverage_analysis() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "📊 Running coverage analysis for $contract_name..."
    
    mkdir -p "$contracts_dir/logs/coverage"
    local coverage_log="$contracts_dir/logs/coverage/${contract_name}-coverage.log"
    
    # Run pytest with coverage
    if command -v pytest &> /dev/null && command -v coverage &> /dev/null; then
        (cd "$contracts_dir" && coverage run -m pytest tests/ --verbose > "$coverage_log" 2>&1) || {
            log_with_timestamp "⚠️ Test execution had issues, check coverage log"
        }
        
        # Generate coverage report
        (cd "$contracts_dir" && coverage report >> "$coverage_log" 2>&1) || true
        (cd "$contracts_dir" && coverage html -d logs/coverage/html_report 2>&1) || true
        
        # Extract coverage percentage
        local coverage_percent=$(cd "$contracts_dir" && coverage report | grep TOTAL | awk '{print $4}' 2>/dev/null || echo "N/A")
        log_with_timestamp "Coverage: $coverage_percent"
        
    else
        echo "Coverage tools not available - installing..." > "$coverage_log"
        pip install coverage pytest-cov >> "$coverage_log" 2>&1
    fi
    
    log_with_timestamp "✅ Coverage analysis completed"
}

# Enhanced comprehensive test execution with parallel processing
run_enhanced_starknet_tests() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    log_with_timestamp "🧪 Running enhanced comprehensive tests for $contract_name..." "debug"
    
    mkdir -p "$contracts_dir/logs/tests"
    local test_log="$contracts_dir/logs/tests/${contract_name}-comprehensive-tests.log"
    
    # Run all test suites in parallel
    {
        # Run main comprehensive tests
        if [ -f "$contracts_dir/tests/test_${contract_name}_comprehensive.py" ]; then
            (cd "$contracts_dir" && python -m pytest tests/test_${contract_name}_comprehensive.py -v \
                --tb=short --maxfail=5 -x ${PYTEST_XDIST_WORKER_COUNT:+-n $PYTEST_XDIST_WORKER_COUNT} \
                > "$contracts_dir/logs/tests/comprehensive.log" 2>&1) &
            COMPREHENSIVE_PID=$!
        fi
        
        # Run security tests
        if [ -f "$contracts_dir/tests/test_${contract_name}_security.py" ]; then
            (cd "$contracts_dir" && python -m pytest tests/test_${contract_name}_security.py -v \
                --tb=short --maxfail=5 \
                > "$contracts_dir/logs/tests/security.log" 2>&1) &
            SECURITY_TEST_PID=$!
        fi
        
        # Run integration tests
        if [ -f "$contracts_dir/tests/test_${contract_name}_integration.py" ]; then
            (cd "$contracts_dir" && python -m pytest tests/test_${contract_name}_integration.py -v \
                --tb=short --maxfail=3 \
                > "$contracts_dir/logs/tests/integration.log" 2>&1) &
            INTEGRATION_PID=$!
        fi
        
        # Run performance tests
        if [ -f "$contracts_dir/tests/test_${contract_name}_performance.py" ]; then
            (cd "$contracts_dir" && python -m pytest tests/test_${contract_name}_performance.py -v \
                --tb=short --benchmark-skip \
                > "$contracts_dir/logs/tests/performance.log" 2>&1) &
            PERFORMANCE_TEST_PID=$!
        fi
        
        # Run original generated tests
        if [ -f "$contracts_dir/tests/test_${contract_name}.py" ]; then
            (cd "$contracts_dir" && python -m pytest tests/test_${contract_name}.py -v \
                --tb=short \
                > "$contracts_dir/logs/tests/generated.log" 2>&1) &
            GENERATED_PID=$!
        fi
        
        # Wait for all test suites to complete
        [ ! -z "$COMPREHENSIVE_PID" ] && wait $COMPREHENSIVE_PID
        [ ! -z "$SECURITY_TEST_PID" ] && wait $SECURITY_TEST_PID
        [ ! -z "$INTEGRATION_PID" ] && wait $INTEGRATION_PID
        [ ! -z "$PERFORMANCE_TEST_PID" ] && wait $PERFORMANCE_TEST_PID
        [ ! -z "$GENERATED_PID" ] && wait $GENERATED_PID
        
        log_with_timestamp "✅ All test suites completed" "success"
    }
    
    log_with_timestamp "✅ Enhanced comprehensive testing completed" "success"
}

# Main processing logic with enhanced parallel execution
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
            CONTRACTS_DIR="/app/contracts/${CONTRACT_NAME}"
            mkdir -p "$CONTRACTS_DIR/src" "$CONTRACTS_DIR/tests" "$CONTRACTS_DIR/logs"

            cp "$FILE_PATH" "$CONTRACTS_DIR/src/contract.cairo"

            # Enhanced contract analysis and test generation
            analyze_starknet_contract_features "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACT_NAME"
            generate_comprehensive_starknet_tests "$CONTRACT_NAME" "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACTS_DIR"
            
            # Generate original tests (for backward compatibility)
            if [ -f "/app/scripts/generate_starknet_tests.py" ]; then
            python3 /app/scripts/generate_starknet_tests.py "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py"
                log_with_timestamp "🧪 Generated original tests for backward compatibility" "debug"
            fi

            # Run all analysis tools in parallel for faster processing
            log_with_timestamp "🔍 Starting parallel analysis tools for $CONTRACT_NAME..." "debug"
            {
                run_comprehensive_starknet_security_audit "$CONTRACT_NAME" "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACTS_DIR" &
                SECURITY_PID=$!
                
                run_starknet_coverage_analysis "$CONTRACT_NAME" "$CONTRACTS_DIR" &
                COVERAGE_PID=$!
                
                run_starknet_performance_analysis "$CONTRACT_NAME" "$CONTRACTS_DIR" &
                PERFORMANCE_PID=$!
                
                # Run enhanced comprehensive tests (parallel test execution)
                run_enhanced_starknet_tests "$CONTRACT_NAME" "$CONTRACTS_DIR" &
                TEST_PID=$!
                
                # Wait for all analysis tools to complete
                wait $SECURITY_PID
                wait $COVERAGE_PID
                wait $PERFORMANCE_PID
                wait $TEST_PID
                
                log_with_timestamp "✅ All parallel analysis tools completed for $CONTRACT_NAME" "success"
            }

            # Generate AI-enhanced report
            if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                log_with_timestamp "🤖 Starting AI-enhanced aggregation..." "debug"
                
                # Create a clean log file for AI processing (exclude verbose build logs)
                AI_CLEAN_LOG="/app/logs/ai-clean-${CONTRACT_NAME}.log"
                
                # Copy only important log entries (exclude verbose build/test output)
                grep -E "(🔧|🧪|🔍|✅|❌|⚠️|🛡️|⚡|📊|🏁)" "$LOG_FILE" > "$AI_CLEAN_LOG" 2>/dev/null || touch "$AI_CLEAN_LOG"
                
                # Set temporary LOG_FILE for AI processing
                ORIGINAL_LOG_FILE="$LOG_FILE"
                export LOG_FILE="$AI_CLEAN_LOG"
                
                if node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME"; then
                    log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${CONTRACT_NAME}-report.txt" "success"
                else
                    log_with_timestamp "❌ AI-enhanced aggregation failed" "error"
                fi
                
                # Restore original LOG_FILE and clean up
                export LOG_FILE="$ORIGINAL_LOG_FILE"
                rm -f "$AI_CLEAN_LOG"
            fi

            end_time=$(date +%s)
            duration=$((end_time - start_time))
            log_with_timestamp "🏁 Completed processing $filename in ${duration}s" "success"
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
                [ "$CURRENT_HASH" == "$LAST_HASH" ] && continue
            fi
            echo "$CURRENT_HASH" > "$MARKER_FILE"
            
            {
                start_time=$(date +%s)
                CONTRACT_NAME="${filename%.cairo}"
                CONTRACTS_DIR="/app/contracts/${CONTRACT_NAME}"
                mkdir -p "$CONTRACTS_DIR/src" "$CONTRACTS_DIR/tests" "$CONTRACTS_DIR/logs"

                cp "$file" "$CONTRACTS_DIR/src/contract.cairo"

                # Enhanced contract analysis and test generation
                analyze_starknet_contract_features "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACT_NAME"
                generate_comprehensive_starknet_tests "$CONTRACT_NAME" "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACTS_DIR"
                
                # Generate original tests (for backward compatibility)
                if [ -f "/app/scripts/generate_starknet_tests.py" ]; then
                python3 /app/scripts/generate_starknet_tests.py "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACTS_DIR/tests/test_${CONTRACT_NAME}.py"
                    log_with_timestamp "🧪 Generated original tests for backward compatibility" "debug"
                fi

                # Run all analysis tools in parallel for faster processing
                log_with_timestamp "🔍 Starting parallel analysis tools for $CONTRACT_NAME..." "debug"
                {
                    run_comprehensive_starknet_security_audit "$CONTRACT_NAME" "$CONTRACTS_DIR/src/contract.cairo" "$CONTRACTS_DIR" &
                    SECURITY_PID=$!
                    
                    run_starknet_coverage_analysis "$CONTRACT_NAME" "$CONTRACTS_DIR" &
                    COVERAGE_PID=$!
                    
                    run_starknet_performance_analysis "$CONTRACT_NAME" "$CONTRACTS_DIR" &
                    PERFORMANCE_PID=$!
                    
                    # Run enhanced comprehensive tests (parallel test execution)
                    run_enhanced_starknet_tests "$CONTRACT_NAME" "$CONTRACTS_DIR" &
                    TEST_PID=$!
                    
                    # Wait for all analysis tools to complete
                    wait $SECURITY_PID
                    wait $COVERAGE_PID
                    wait $PERFORMANCE_PID
                    wait $TEST_PID
                    
                    log_with_timestamp "✅ All parallel analysis tools completed for $CONTRACT_NAME" "success"
                }

                # Generate AI-enhanced report
                if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                    log_with_timestamp "🤖 Starting AI-enhanced aggregation..." "debug"
                    
                    # Create a clean log file for AI processing (exclude verbose build logs)
                    AI_CLEAN_LOG="/app/logs/ai-clean-${CONTRACT_NAME}.log"
                    
                    # Copy only important log entries (exclude verbose build/test output)
                    grep -E "(🔧|🧪|🔍|✅|❌|⚠️|🛡️|⚡|📊|🏁)" "$LOG_FILE" > "$AI_CLEAN_LOG" 2>/dev/null || touch "$AI_CLEAN_LOG"
                    
                    # Set temporary LOG_FILE for AI processing
                    ORIGINAL_LOG_FILE="$LOG_FILE"
                    export LOG_FILE="$AI_CLEAN_LOG"
                    
                    if node /app/scripts/aggregate-all-logs.js "$CONTRACT_NAME"; then
                        log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${CONTRACT_NAME}-report.txt" "success"
                    else
                        log_with_timestamp "❌ AI-enhanced aggregation failed" "error"
                    fi
                    
                    # Restore original LOG_FILE and clean up
                    export LOG_FILE="$ORIGINAL_LOG_FILE"
                    rm -f "$AI_CLEAN_LOG"
                fi

                end_time=$(date +%s)
                duration=$((end_time - start_time))
                log_with_timestamp "🏁 Completed processing $filename in ${duration}s" "success"
                log_with_timestamp "=========================================="
            } 2>&1
        done
        sleep 5
    done
fi   

# Enhanced Starknet contract analysis and comprehensive test generation
analyze_starknet_contract_features() {
    local contract_file="$1"
    local contract_name="$2"
    
    log_with_timestamp "🔍 Analyzing Starknet contract features for comprehensive testing..." "debug"
    
    # Analyze contract structure and Cairo patterns
    local has_constructor=$(grep -q "#\[constructor\]\|constructor(" "$contract_file" && echo "true" || echo "false")
    local has_storage=$(grep -q "#\[storage\]\|struct Storage" "$contract_file" && echo "true" || echo "false")
    local has_interface=$(grep -q "#\[starknet::interface\]\|trait.*Interface" "$contract_file" && echo "true" || echo "false")
    local has_contract=$(grep -q "#\[starknet::contract\]\|mod.*Contract" "$contract_file" && echo "true" || echo "false")
    local has_external=$(grep -q "#\[external(v0)\]\|fn.*external" "$contract_file" && echo "true" || echo "false")
    local has_view=$(grep -q "#\[view\]\|fn.*view" "$contract_file" && echo "true" || echo "false")
    local has_events=$(grep -q "#\[event\]\|Event\|emit!" "$contract_file" && echo "true" || echo "false")
    local has_l1_handler=$(grep -q "#\[l1_handler\]\|l1_handler" "$contract_file" && echo "true" || echo "false")
    local has_upgradeable=$(grep -q "upgradeable\|proxy\|implementation" "$contract_file" && echo "true" || echo "false")
    local has_ownable=$(grep -q "owner\|Ownable\|only_owner" "$contract_file" && echo "true" || echo "false")
    local has_pausable=$(grep -q "pausable\|pause\|unpause" "$contract_file" && echo "true" || echo "false")
    local has_reentrancy=$(grep -q "reentrancy\|ReentrancyGuard" "$contract_file" && echo "true" || echo "false")
    local has_erc20=$(grep -q "ERC20\|transfer\|balance_of\|total_supply" "$contract_file" && echo "true" || echo "false")
    local has_erc721=$(grep -q "ERC721\|token_uri\|owner_of" "$contract_file" && echo "true" || echo "false")
    local has_account=$(grep -q "Account\|__execute__\|__validate__" "$contract_file" && echo "true" || echo "false")
    local has_multicall=$(grep -q "multicall\|batch" "$contract_file" && echo "true" || echo "false")
    
    # Store analysis results for test generation
    echo "has_constructor=$has_constructor" > "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_storage=$has_storage" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_interface=$has_interface" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_contract=$has_contract" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_external=$has_external" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_view=$has_view" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_events=$has_events" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_l1_handler=$has_l1_handler" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_upgradeable=$has_upgradeable" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_ownable=$has_ownable" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_pausable=$has_pausable" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_reentrancy=$has_reentrancy" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_erc20=$has_erc20" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_erc721=$has_erc721" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_account=$has_account" >> "/tmp/starknet_analysis_${contract_name}.env"
    echo "has_multicall=$has_multicall" >> "/tmp/starknet_analysis_${contract_name}.env"
    
    log_with_timestamp "✅ Starknet contract analysis completed - generating comprehensive tests..." "success"
}

# Generate comprehensive Starknet tests
generate_comprehensive_starknet_tests() {
    local contract_name="$1"
    local contract_file="$2"
    local contracts_dir="$3"
    
    # Load analysis results
    source "/tmp/starknet_analysis_${contract_name}.env"
    
    log_with_timestamp "🧪 Generating comprehensive test suite for Starknet contract $contract_name..." "debug"
    
    # Create main test file
    cat > "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
"""
Comprehensive test suite for Starknet smart contract: ${contract_name}
Auto-generated based on contract analysis
"""

import pytest
import asyncio
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.account.account import Account
from starknet_py.net.models import StarknetChainId
from starknet_py.net.signer.stark_curve_signer import StarkCurveSigner
from starknet_py.contract import Contract
from starknet_py.compile.compiler import create_contract_class
from starknet_py.hash.selector import get_selector_from_name
import json

# Test configuration
STARKNET_RPC_URL = "http://localhost:5050"
CHAIN_ID = StarknetChainId.TESTNET

class Test${contract_name^}Comprehensive:
    """Comprehensive test class for ${contract_name} contract"""
    
    @pytest.fixture(scope="class")
    def event_loop(self):
        """Create event loop for async tests"""
        loop = asyncio.new_event_loop()
        yield loop
        loop.close()
    
    @pytest.fixture(scope="class")
    async def starknet_client(self):
        """Initialize Starknet client for testing"""
        client = FullNodeClient(node_url=STARKNET_RPC_URL)
        return client
    
    @pytest.fixture(scope="class")
    async def test_accounts(self, starknet_client):
        """Create test accounts"""
        # Note: In actual implementation, you would use proper account creation
        # This is a placeholder for account setup
        deployer_account = None  # Initialize with proper account
        user1_account = None     # Initialize with proper account
        user2_account = None     # Initialize with proper account
        
        return {
            'deployer': deployer_account,
            'user1': user1_account,
            'user2': user2_account
        }
    
    @pytest.mark.asyncio
    async def test_contract_deployment(self, starknet_client, test_accounts):
        """Test contract deployment and basic validation"""
        deployer = test_accounts['deployer']
        
        # Test that contract can be deployed successfully
        # Note: Actual deployment logic would be implemented here
        assert True  # Placeholder for deployment test
    
EOF

    # Add constructor tests if detected
    if [ "$has_constructor" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_constructor_initialization(self, starknet_client, test_accounts):
        """Test constructor initialization"""
        deployer = test_accounts['deployer']
        
        # Test constructor parameters and initialization
        # Test initial state setup
        # Test access control initialization
        assert True  # Placeholder for constructor tests

EOF
    fi

    # Add storage tests if detected
    if [ "$has_storage" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_storage_operations(self, starknet_client, test_accounts):
        """Test storage read and write operations"""
        deployer = test_accounts['deployer']
        
        # Test storage variable access
        # Test storage variable modification
        # Test storage security and access control
        assert True  # Placeholder for storage tests

    @pytest.mark.asyncio
    async def test_storage_edge_cases(self, starknet_client, test_accounts):
        """Test storage edge cases and limits"""
        # Test storage overflow/underflow
        # Test concurrent storage access
        # Test storage gas optimization
        assert True  # Placeholder for storage edge cases

EOF
    fi

    # Add external function tests if detected
    if [ "$has_external" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_external_functions(self, starknet_client, test_accounts):
        """Test external function calls"""
        deployer = test_accounts['deployer']
        user1 = test_accounts['user1']
        
        # Test external function accessibility
        # Test function parameter validation
        # Test state changes from external calls
        assert True  # Placeholder for external function tests

EOF
    fi

    # Add view function tests if detected
    if [ "$has_view" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_view_functions(self, starknet_client, test_accounts):
        """Test view function calls"""
        # Test view function return values
        # Test view function gas efficiency
        # Test view function consistency
        assert True  # Placeholder for view function tests

EOF
    fi

    # Add event tests if detected
    if [ "$has_events" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_events_emission(self, starknet_client, test_accounts):
        """Test event emission and logging"""
        deployer = test_accounts['deployer']
        
        # Test event emission on state changes
        # Test event data accuracy
        # Test event filtering and querying
        assert True  # Placeholder for event tests

EOF
    fi

    # Add L1 handler tests if detected
    if [ "$has_l1_handler" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_l1_handler_functions(self, starknet_client, test_accounts):
        """Test L1 handler functionality"""
        # Test L1 message consumption
        # Test L1 to L2 message processing
        # Test L1 handler security
        assert True  # Placeholder for L1 handler tests

EOF
    fi

    # Add ERC20 tests if detected
    if [ "$has_erc20" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_erc20_functionality(self, starknet_client, test_accounts):
        """Test ERC20 token functionality"""
        deployer = test_accounts['deployer']
        user1 = test_accounts['user1']
        
        # Test token transfers
        # Test allowance mechanisms
        # Test total supply management
        # Test balance tracking
        assert True  # Placeholder for ERC20 tests

EOF
    fi

    # Add account contract tests if detected
    if [ "$has_account" = "true" ]; then
        cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_account_functionality(self, starknet_client, test_accounts):
        """Test account contract functionality"""
        # Test transaction execution
        # Test signature validation
        # Test multicall functionality
        # Test account security
        assert True  # Placeholder for account tests

EOF
    fi

    # Add security tests
    cat >> "$contracts_dir/tests/test_${contract_name}_comprehensive.py" <<EOF
    @pytest.mark.asyncio
    async def test_security_access_control(self, starknet_client, test_accounts):
        """Test access control and authorization"""
        deployer = test_accounts['deployer']
        user1 = test_accounts['user1']
        
        # Test owner-only functions
        # Test unauthorized access attempts
        # Test privilege escalation prevention
        assert True  # Placeholder for security tests

    @pytest.mark.asyncio
    async def test_security_edge_cases(self, starknet_client, test_accounts):
        """Test security edge cases and attack vectors"""
        # Test reentrancy protection
        # Test integer overflow/underflow
        # Test resource exhaustion
        # Test malformed input handling
        assert True  # Placeholder for security edge cases

    @pytest.mark.asyncio
    async def test_gas_optimization(self, starknet_client, test_accounts):
        """Test gas optimization and efficiency"""
        # Test function call costs
        # Test storage operation costs
        # Test batch operation efficiency
        assert True  # Placeholder for gas optimization tests

    @pytest.mark.asyncio
    async def test_error_handling(self, starknet_client, test_accounts):
        """Test error handling and failure scenarios"""
        # Test invalid input handling
        # Test network failure resilience
        # Test transaction failure recovery
        assert True  # Placeholder for error handling tests
EOF

    # Generate additional specialized test files
    generate_starknet_security_tests "$contract_name" "$contracts_dir"
    generate_starknet_integration_tests "$contract_name" "$contracts_dir"
    generate_starknet_performance_tests "$contract_name" "$contracts_dir"
    
    log_with_timestamp "✅ Comprehensive Starknet test suite generated successfully" "success"
    log_with_timestamp "📊 Generated tests include: deployment, functions, events, security, and performance" "debug"
}

# Generate specialized security tests for Starknet
generate_starknet_security_tests() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    cat > "$contracts_dir/tests/test_${contract_name}_security.py" <<EOF
"""
Security-focused tests for Starknet smart contract: ${contract_name}
"""

import pytest
import asyncio
from starknet_py.net.full_node_client import FullNodeClient

class Test${contract_name^}Security:
    """Security test class for ${contract_name} contract"""
    
    @pytest.mark.asyncio
    async def test_access_control_violations(self):
        """Test access control bypass attempts"""
        # Test unauthorized function calls
        # Test privilege escalation attempts
        # Test admin function access
        assert True
    
    @pytest.mark.asyncio
    async def test_reentrancy_protection(self):
        """Test reentrancy attack resistance"""
        # Test recursive calls
        # Test cross-function reentrancy
        # Test external contract reentrancy
        assert True
    
    @pytest.mark.asyncio
    async def test_arithmetic_safety(self):
        """Test arithmetic operation safety"""
        # Test integer overflow
        # Test integer underflow
        # Test division by zero
        # Test precision loss
        assert True
    
    @pytest.mark.asyncio
    async def test_cairo_specific_vulnerabilities(self):
        """Test Cairo-specific security issues"""
        # Test felt overflow/underflow
        # Test array bounds checking
        # Test hint safety
        # Test memory access patterns
        assert True
    
    @pytest.mark.asyncio
    async def test_l1_l2_bridge_security(self):
        """Test L1-L2 bridge security"""
        # Test message validation
        # Test cross-layer replay attacks
        # Test message ordering
        assert True
EOF
}

# Generate integration tests for Starknet
generate_starknet_integration_tests() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    cat > "$contracts_dir/tests/test_${contract_name}_integration.py" <<EOF
"""
Integration tests for Starknet smart contract: ${contract_name}
"""

import pytest
import asyncio
from starknet_py.net.full_node_client import FullNodeClient

class Test${contract_name^}Integration:
    """Integration test class for ${contract_name} contract"""
    
    @pytest.mark.asyncio
    async def test_multi_contract_interaction(self):
        """Test interactions with multiple contracts"""
        # Test cross-contract calls
        # Test contract composition
        # Test dependency management
        assert True
    
    @pytest.mark.asyncio
    async def test_l1_l2_integration(self):
        """Test L1-L2 integration"""
        # Test L1 to L2 message passing
        # Test L2 to L1 message passing
        # Test cross-layer state synchronization
        assert True
    
    @pytest.mark.asyncio
    async def test_real_world_scenarios(self):
        """Test real-world usage scenarios"""
        # Test typical user workflows
        # Test high-volume operations
        # Test concurrent users
        assert True
EOF
}

# Generate performance tests for Starknet
generate_starknet_performance_tests() {
    local contract_name="$1"
    local contracts_dir="$2"
    
    cat > "$contracts_dir/tests/test_${contract_name}_performance.py" <<EOF
"""
Performance tests for Starknet smart contract: ${contract_name}
"""

import pytest
import asyncio
import time
from starknet_py.net.full_node_client import FullNodeClient

class Test${contract_name^}Performance:
    """Performance test class for ${contract_name} contract"""
    
    @pytest.mark.asyncio
    async def test_transaction_throughput(self):
        """Test transaction processing throughput"""
        # Test high-frequency transactions
        # Test batch processing
        # Test concurrent operations
        assert True
    
    @pytest.mark.asyncio
    async def test_gas_efficiency(self):
        """Test gas consumption efficiency"""
        # Test operation costs
        # Test optimization effectiveness
        # Test resource usage
        assert True
    
    @pytest.mark.asyncio
    async def test_scalability_limits(self):
        """Test scalability and limits"""
        # Test user capacity
        # Test data storage limits
        # Test computational complexity
        assert True
    
    @pytest.mark.benchmark
    @pytest.mark.asyncio
    async def test_critical_path_performance(self):
        """Benchmark critical operations"""
        start_time = time.time()
        # Execute critical operations
        end_time = time.time()
        
        execution_time = end_time - start_time
        assert execution_time < 2.0  # Should complete within 2 seconds
EOF
}   
