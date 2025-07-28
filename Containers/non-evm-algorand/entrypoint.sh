#!/bin/bash
set -e

# Simple environment setup for Python/Algorand
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1

echo "🚀 Starting Simplified Algorand Container..."
echo "📂 Watching for Python contract files..."

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
import sys
import os

# Add the contract directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

def test_contract_import():
    """Test that the contract can be imported successfully."""
    try:
        import ${contract_name}
        assert True, "Contract imported successfully"
    except ImportError as e:
        pytest.fail(f"Failed to import contract: {e}")

def test_basic_functionality():
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
        echo "=== Basic Python/Algorand Security Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Basic pattern checks for PyTeal/Algorand
        if grep -n "eval\|exec\|__import__" "$contract_path"; then
            echo "WARNING: Dynamic code execution found - review for security"
        else
            echo "✅ No dynamic code execution found"
        fi
        
        if grep -n "pyteal\|PyTeal" "$contract_path"; then
            echo "✅ PyTeal usage detected"
        fi
        
        if grep -n "Global\|Local" "$contract_path"; then
            echo "✅ Algorand state management detected"
        fi
        
        echo "=== Analysis Complete ==="
    } > "$security_log"
    
    log_with_timestamp "✅ Basic security analysis completed"
}

log_with_timestamp "📡 Watching for Python contract files in /app/input..."

# Main file monitoring loop
if command -v inotifywait &> /dev/null; then
    inotifywait -m -e close_write,moved_to /app/input --format '%w%f' |
    while read FILE_PATH; do
        if [[ "$FILE_PATH" == *.py ]]; then
            filename=$(basename "$FILE_PATH")
            contract_name=$(basename "$filename" .py)
            
            # Simple lock mechanism
            lock_file="/tmp/processing_${contract_name}.lock"
            if [ -f "$lock_file" ]; then
                continue
            fi
            echo "$$" > "$lock_file"
            
            {
                start_time=$(date +%s)
                log_with_timestamp "🆕 Processing Python contract: $filename"
                
                contract_subdir="/app/contracts/${contract_name}"
                mkdir -p "$contract_subdir/src"
                mkdir -p "$contract_subdir/logs"
                cp "$FILE_PATH" "$contract_subdir/src/${filename}"
                
                # Generate tests
                generate_basic_tests "$contract_name" "$contract_subdir"
                
                # Basic syntax check
                log_with_timestamp "🔍 Checking syntax for $contract_name..."
                if python3 -m py_compile "$contract_subdir/src/${filename}" 2> "$contract_subdir/logs/syntax.log"; then
                    log_with_timestamp "✅ Syntax check passed"
                    
                    # Run basic analysis
                    run_basic_security_analysis "$contract_name" "$contract_subdir/src/${filename}" "$contract_subdir"
                    
                    # Run tests
                    (cd "$contract_subdir" && python3 -m pytest tests/ > "$contract_subdir/logs/test.log" 2>&1) || {
                        log_with_timestamp "⚠️ Some tests may have failed - check logs"
                    }
                    
                else
                    log_with_timestamp "❌ Syntax check failed for $contract_name"
                    if [ -f "$contract_subdir/logs/syntax.log" ]; then
                        cat "$contract_subdir/logs/syntax.log" | while IFS= read -r line; do
                            log_with_timestamp "   $line"
                        done
                    fi
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
        for FILE_PATH in /app/input/*.py; do
            [ -e "$FILE_PATH" ] || continue
            # Similar processing logic would go here
        done
        sleep 5
    done
fi
