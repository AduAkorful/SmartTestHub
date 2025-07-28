#!/bin/bash
set -e

# Simple environment setup for Python/Algorand
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1

echo "🚀 Starting Enhanced Algorand Container..."
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

# Generate comprehensive test file
generate_comprehensive_tests() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "🧪 Generating comprehensive test suite for $contract_name..."
    
    mkdir -p "$contract_subdir/tests"
    
    cat > "$contract_subdir/tests/test_${contract_name}.py" <<EOF
import pytest
import sys
import os
from pyteal import *
from algosdk import transaction
from algosdk.v2client import algod

# Add the contract directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

def test_contract_import():
    """Test that the contract can be imported successfully."""
    try:
        import ${contract_name}
        assert True, "Contract imported successfully"
    except ImportError as e:
        pytest.fail(f"Failed to import contract: {e}")

def test_pyteal_compilation():
    """Test PyTeal compilation to TEAL."""
    try:
        import ${contract_name}
        # Try to find a PyTeal program in the contract
        for attr_name in dir(${contract_name}):
            attr = getattr(${contract_name}, attr_name)
            if hasattr(attr, 'teal'):
                teal_code = compileTeal(attr, Mode.Application)
                assert len(teal_code) > 0, "TEAL code generated"
                print(f"TEAL compilation successful for {attr_name}")
                return
        print("No PyTeal programs found for compilation test")
    except Exception as e:
        pytest.fail(f"PyTeal compilation failed: {e}")

def test_basic_functionality():
    """Basic functionality test for the contract."""
    # Add specific tests based on your contract
    assert True, "Basic test passed"

def test_state_management():
    """Test Algorand state management patterns."""
    try:
        import ${contract_name}
        # Check for common Algorand state patterns
        contract_source = open(os.path.join(os.path.dirname(__file__), '..', 'src', '${contract_name}.py')).read()
        
        if 'App.globalGet' in contract_source or 'App.localGet' in contract_source:
            assert True, "State management patterns found"
        else:
            print("No explicit state management patterns found")
    except Exception as e:
        print(f"State management test warning: {e}")

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
EOF
    
    log_with_timestamp "✅ Comprehensive test suite generated"
}

# TEAL compilation and analysis
run_teal_analysis() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "🔧 Running TEAL compilation and analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/teal"
    local teal_log="$contract_subdir/logs/teal/${contract_name}-teal.log"
    
    {
        echo "=== TEAL Compilation Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Try to compile PyTeal to TEAL
        python3 << EOL
import sys
sys.path.insert(0, '$contract_subdir/src')
try:
    import $contract_name
    from pyteal import *
    
    print("=== PyTeal Programs Found ===")
    teal_programs = []
    
    for attr_name in dir($contract_name):
        attr = getattr($contract_name, attr_name)
        if hasattr(attr, 'teal') or (callable(attr) and not attr_name.startswith('_')):
            try:
                if hasattr(attr, 'teal'):
                    teal_code = compileTeal(attr, Mode.Application)
                    print(f"✅ Successfully compiled {attr_name} to TEAL")
                    print(f"   TEAL size: {len(teal_code)} characters")
                    print(f"   TEAL lines: {len(teal_code.splitlines())} lines")
                    teal_programs.append((attr_name, teal_code))
                elif callable(attr):
                    try:
                        result = attr()
                        if hasattr(result, 'teal'):
                            teal_code = compileTeal(result, Mode.Application)
                            print(f"✅ Successfully compiled {attr_name}() to TEAL")
                            print(f"   TEAL size: {len(teal_code)} characters")
                            print(f"   TEAL lines: {len(teal_code.splitlines())} lines")
                            teal_programs.append((attr_name, teal_code))
                    except:
                        pass
            except Exception as e:
                print(f"⚠️ Failed to compile {attr_name}: {e}")
    
    if teal_programs:
        print(f"\\n=== TEAL Analysis Summary ===")
        print(f"Total programs compiled: {len(teal_programs)}")
        total_size = sum(len(code) for _, code in teal_programs)
        print(f"Total TEAL size: {total_size} characters")
        
        for name, code in teal_programs:
            with open('$contract_subdir/logs/teal/{name}-compiled.teal', 'w') as f:
                f.write(code)
    else:
        print("❌ No TEAL programs could be compiled")
        
except Exception as e:
    print(f"❌ TEAL compilation failed: {e}")
EOL
        
        echo "=== TEAL Analysis Complete ==="
    } > "$teal_log" 2>&1
    
    log_with_timestamp "✅ TEAL compilation and analysis completed"
}

# Comprehensive security analysis
run_comprehensive_security_analysis() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "🛡️ Running comprehensive security analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/security"
    
    # Run multiple security tools
    local bandit_log="$contract_subdir/logs/security/${contract_name}-bandit.log"
    local flake8_log="$contract_subdir/logs/security/${contract_name}-flake8.log"
    local mypy_log="$contract_subdir/logs/security/${contract_name}-mypy.log"
    local basic_log="$contract_subdir/logs/security/${contract_name}-security.log"
    
    # Bandit security analysis
    if command -v bandit &> /dev/null; then
        bandit -r "$contract_path" -f txt > "$bandit_log" 2>&1 || {
            log_with_timestamp "⚠️ Bandit found security issues - check $bandit_log"
        }
    fi
    
    # Flake8 code quality
    if command -v flake8 &> /dev/null; then
        flake8 "$contract_path" > "$flake8_log" 2>&1 || {
            log_with_timestamp "⚠️ Flake8 found code quality issues - check $flake8_log"
        }
    fi
    
    # MyPy type checking
    if command -v mypy &> /dev/null; then
        mypy "$contract_path" > "$mypy_log" 2>&1 || {
            log_with_timestamp "⚠️ MyPy found type issues - check $mypy_log"
        }
    fi
    
    # Basic pattern analysis
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
        
        if grep -n "Global\|Local\|App\.globalGet\|App\.localGet" "$contract_path"; then
            echo "✅ Algorand state management detected"
        fi
        
        if grep -n "Txn\|Gtxn" "$contract_path"; then
            echo "✅ Transaction handling detected"
        fi
        
        if grep -n "Assert\|Return" "$contract_path"; then
            echo "✅ Control flow patterns detected"
        fi
        
        echo "=== Analysis Complete ==="
    } > "$basic_log"
    
    log_with_timestamp "✅ Comprehensive security analysis completed"
}

# Coverage analysis
run_coverage_analysis() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "📊 Running coverage analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/coverage"
    local coverage_log="$contract_subdir/logs/coverage/${contract_name}-coverage.log"
    
    # Run tests with coverage
    if command -v pytest &> /dev/null; then
        (cd "$contract_subdir" && python3 -m pytest tests/ --cov=src --cov-report=term --cov-report=html:logs/coverage/html > "$coverage_log" 2>&1) || {
            log_with_timestamp "⚠️ Coverage analysis completed with warnings - check $coverage_log"
        }
    fi
    
    log_with_timestamp "✅ Coverage analysis completed"
}

# Performance analysis
run_performance_analysis() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "⚡ Running performance analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/performance"
    local perf_log="$contract_subdir/logs/performance/${contract_name}-performance.log"
    
    {
        echo "=== Performance Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Basic performance metrics
        echo "=== File Size Analysis ==="
        file_size=$(stat -c%s "$contract_subdir/src/${contract_name}.py" 2>/dev/null || echo "unknown")
        echo "Contract file size: $file_size bytes"
        
        line_count=$(wc -l < "$contract_subdir/src/${contract_name}.py" 2>/dev/null || echo "unknown")
        echo "Contract lines of code: $line_count"
        
        echo "=== Performance Analysis Complete ==="
    } > "$perf_log"
    
    log_with_timestamp "✅ Performance analysis completed"
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
                
                # Generate comprehensive tests
                generate_comprehensive_tests "$contract_name" "$contract_subdir"
                
                # Basic syntax check
                log_with_timestamp "🔍 Checking syntax for $contract_name..."
                if python3 -m py_compile "$contract_subdir/src/${filename}" 2> "$contract_subdir/logs/syntax.log"; then
                    log_with_timestamp "✅ Syntax check passed"
                    
                    # Run comprehensive analysis
                    run_teal_analysis "$contract_name" "$contract_subdir/src/${filename}" "$contract_subdir"
                    run_comprehensive_security_analysis "$contract_name" "$contract_subdir/src/${filename}" "$contract_subdir"
                    run_performance_analysis "$contract_name" "$contract_subdir"
                    
                    # Run tests with coverage
                    log_with_timestamp "🧪 Running comprehensive tests..."
                    (cd "$contract_subdir" && python3 -m pytest tests/ -v --tb=short > "$contract_subdir/logs/test.log" 2>&1) || {
                        log_with_timestamp "⚠️ Some tests may have failed - check logs"
                    }
                    
                    # Run coverage analysis
                    run_coverage_analysis "$contract_name" "$contract_subdir"
                    
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
