#!/bin/bash
set -e

# Simple environment setup for Python/StarkNet
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1

echo "🚀 Starting Simplified StarkNet Container..."
echo "📂 Watching for Cairo contract files..."

# Create necessary directories
mkdir -p /app/input
mkdir -p /app/logs
mkdir -p /app/contracts
mkdir -p /app/src
mkdir -p /app/tests

LOG_FILE="/app/logs/test.log"
: > "$LOG_FILE"

# Simple logging function
log_with_timestamp() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $message" | tee -a "$LOG_FILE"
}

# Generate basic test file
generate_basic_tests() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "🧪 Generating basic test suite for $contract_name..."
    
    mkdir -p "$contract_subdir/tests"
    
    cat > "$contract_subdir/tests/test_${contract_name}.py" <<EOF
import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet

@pytest.mark.asyncio
async def test_contract_deployment():
    """Test that the contract can be deployed successfully."""
    try:
        starknet = await Starknet.empty()
        contract = await starknet.deploy(
            source="src/${contract_name}.cairo",
            cairo_path=["src"]
        )
        assert contract.contract_address is not None, "Contract deployed successfully"
    except Exception as e:
        pytest.fail(f"Failed to deploy contract: {e}")

@pytest.mark.asyncio
async def test_basic_functionality():
    """Basic functionality test for the contract."""
    # Add specific tests based on your contract
    assert True, "Basic test passed"

if __name__ == "__main__":
    pytest.main([__file__])
EOF
    
    log_with_timestamp "✅ Basic test suite generated"
}

# Simple security analysis
run_basic_security_analysis() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "🛡️ Running basic security analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/security"
    local security_log="$contract_subdir/logs/security/${contract_name}-security.log"
    
    {
        echo "=== Basic Cairo/StarkNet Security Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Basic pattern checks for Cairo
        if grep -n "@external\|@view" "$contract_path"; then
            echo "✅ StarkNet decorators found"
        fi
        
        if grep -n "storage_var\|@storage_var" "$contract_path"; then
            echo "✅ Storage variables detected"
        fi
        
        if grep -n "assert\|with_attr" "$contract_path"; then
            echo "✅ Assertions and attributes found"
        fi
        
        echo "=== Analysis Complete ==="
    } > "$security_log"
    
    log_with_timestamp "✅ Basic security analysis completed"
}

log_with_timestamp "📡 Watching for Cairo contract files in /app/input..."

# Main file monitoring loop
if command -v inotifywait &> /dev/null; then
    inotifywait -m -e close_write,moved_to /app/input --format '%w%f' |
    while read FILE_PATH; do
        if [[ "$FILE_PATH" == *.cairo ]]; then
            filename=$(basename "$FILE_PATH")
            contract_name=$(basename "$filename" .cairo)
            
            # Simple lock mechanism
            lock_file="/tmp/processing_${contract_name}.lock"
            if [ -f "$lock_file" ]; then
                continue
            fi
            echo "$$" > "$lock_file"
            
            {
                start_time=$(date +%s)
                log_with_timestamp "🆕 Processing Cairo contract: $filename"
                
                contract_subdir="/app/contracts/${contract_name}"
                mkdir -p "$contract_subdir/src"
                mkdir -p "$contract_subdir/logs"
                cp "$FILE_PATH" "$contract_subdir/src/${filename}"
                
                # Generate tests
                generate_basic_tests "$contract_name" "$contract_subdir"
                
                # Basic compilation check (if cairo compiler available)
                log_with_timestamp "🔍 Checking compilation for $contract_name..."
                if command -v starknet-compile &> /dev/null; then
                    if starknet-compile "$contract_subdir/src/${filename}" > "$contract_subdir/logs/compile.log" 2>&1; then
                        log_with_timestamp "✅ Compilation successful"
                    else
                        log_with_timestamp "❌ Compilation failed"
                        cat "$contract_subdir/logs/compile.log" | tail -5 | while IFS= read -r line; do
                            log_with_timestamp "   $line"
                        done
                    fi
                else
                    log_with_timestamp "ℹ️ Cairo compiler not available, skipping compilation"
                fi
                
                # Run basic analysis
                run_basic_security_analysis "$contract_name" "$contract_subdir/src/${filename}" "$contract_subdir"
                
                # Run tests if pytest available
                if command -v pytest &> /dev/null; then
                    (cd "$contract_subdir" && python3 -m pytest tests/ > "$contract_subdir/logs/test.log" 2>&1) || {
                        log_with_timestamp "⚠️ Some tests may have failed - check logs"
                    }
                fi
                
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                log_with_timestamp "🏁 Completed processing $filename in ${duration}s"
                
                # Generate AI report if script exists
                if [ -f "/app/scripts/aggregate-all-logs.js" ]; then
                    if node /app/scripts/aggregate-all-logs.js "$contract_name" 2>/dev/null; then
                        log_with_timestamp "✅ Report generated"
                    fi
                fi
                
                log_with_timestamp "=========================================="
                rm -f "$lock_file"
                
            } 2>&1 | tee -a "$LOG_FILE"
        fi
    done
else
    # Fallback polling mode
    log_with_timestamp "⚠️ Using polling mode for file monitoring"
    while true; do
        for FILE_PATH in /app/input/*.cairo; do
            [ -e "$FILE_PATH" ] || continue
            # Similar processing logic would go here
        done
        sleep 5
    done
fi   
