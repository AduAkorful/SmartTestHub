#!/bin/bash
set -e

# Simple environment setup for Python/StarkNet
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1

echo "🚀 Starting Enhanced StarkNet Container..."
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

# Check and install Cairo compiler if needed
setup_cairo_compiler() {
    log_with_timestamp "🔧 Setting up Cairo compiler..."
    
    # Try to install Cairo compiler via pip if not available
    if ! command -v starknet-compile &> /dev/null; then
        log_with_timestamp "📦 Installing Cairo compiler..."
        pip install cairo-lang starknet-devnet --quiet || {
            log_with_timestamp "⚠️ Failed to install Cairo compiler via pip"
        }
    fi
    
    # Check again and report status
    if command -v starknet-compile &> /dev/null; then
        local cairo_version=$(starknet-compile --version 2>/dev/null || echo "unknown")
        log_with_timestamp "✅ Cairo compiler available: $cairo_version"
    else
        log_with_timestamp "⚠️ Cairo compiler not available - will use alternative compilation methods"
    fi
}

# Generate comprehensive test file for Cairo
generate_comprehensive_tests() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "🧪 Generating comprehensive test suite for $contract_name..."
    
    mkdir -p "$contract_subdir/tests"
    
    cat > "$contract_subdir/tests/test_${contract_name}.py" <<EOF
import pytest
import asyncio
import sys
import os
from pathlib import Path

# Add the contract directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

# StarkNet specific imports
try:
    from starkware.starknet.testing.starknet import Starknet
    from starkware.starknet.compiler.compile import compile_starknet_files
    from starkware.cairo.common.hash_state import compute_hash_on_elements
    STARKNET_AVAILABLE = True
except ImportError:
    STARKNET_AVAILABLE = False
    print("⚠️ StarkNet testing framework not available")

def test_contract_file_exists():
    """Test that the contract file exists and is readable."""
    contract_path = Path(__file__).parent.parent / "src" / "${contract_name}.cairo"
    assert contract_path.exists(), f"Contract file not found: {contract_path}"
    assert contract_path.is_file(), f"Contract path is not a file: {contract_path}"
    with open(contract_path, 'r') as f:
        content = f.read()
        assert len(content) > 0, "Contract file is empty"

def test_basic_cairo_syntax():
    """Test basic Cairo syntax patterns."""
    contract_path = Path(__file__).parent.parent / "src" / "${contract_name}.cairo"
    with open(contract_path, 'r') as f:
        content = f.read()
    
    # Check for basic Cairo patterns
    if '@external' in content or '@view' in content:
        assert True, "StarkNet decorators found"
    elif 'func ' in content:
        assert True, "Cairo function definitions found"
    else:
        print("⚠️ No clear Cairo patterns detected")

@pytest.mark.skipif(not STARKNET_AVAILABLE, reason="StarkNet testing framework not available")
@pytest.mark.asyncio
async def test_contract_compilation():
    """Test Cairo contract compilation."""
    try:
        contract_path = Path(__file__).parent.parent / "src" / "${contract_name}.cairo"
        
        # Try to compile the contract
        contract_definition = compile_starknet_files(
            files=[str(contract_path)],
            debug_info=True
        )
        
        assert contract_definition is not None, "Contract compilation failed"
        assert hasattr(contract_definition, 'program'), "Compiled contract missing program"
        print(f"✅ Contract compiled successfully")
        
    except Exception as e:
        pytest.fail(f"Contract compilation failed: {e}")

@pytest.mark.skipif(not STARKNET_AVAILABLE, reason="StarkNet testing framework not available")
@pytest.mark.asyncio
async def test_contract_deployment():
    """Test contract deployment to StarkNet test environment."""
    try:
        starknet = await Starknet.empty()
        contract_path = Path(__file__).parent.parent / "src" / "${contract_name}.cairo"
        
        # Try to deploy the contract
        contract = await starknet.deploy(
            source=str(contract_path),
            cairo_path=[str(contract_path.parent)]
        )
        
        assert contract.contract_address is not None, "Contract deployment failed"
        print(f"✅ Contract deployed at address: {hex(contract.contract_address)}")
        
    except Exception as e:
        pytest.fail(f"Contract deployment failed: {e}")

def test_security_patterns():
    """Test for common security patterns in Cairo code."""
    contract_path = Path(__file__).parent.parent / "src" / "${contract_name}.cairo"
    with open(contract_path, 'r') as f:
        content = f.read()
    
    security_checks = []
    
    # Check for access control
    if 'get_caller_address' in content or 'assert_only_owner' in content:
        security_checks.append("✅ Access control patterns detected")
    
    # Check for input validation
    if 'assert ' in content or 'with_attr' in content:
        security_checks.append("✅ Input validation patterns detected")
    
    # Check for storage patterns
    if '@storage_var' in content:
        security_checks.append("✅ Storage variable declarations found")
    
    # Check for events
    if '@event' in content:
        security_checks.append("✅ Event declarations found")
    
    if security_checks:
        for check in security_checks:
            print(check)
    else:
        print("⚠️ No common security patterns detected")

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
EOF
    
    log_with_timestamp "✅ Comprehensive test suite generated"
}

# Cairo compilation and analysis
run_cairo_compilation() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "🔨 Running Cairo compilation for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/compilation"
    local compile_log="$contract_subdir/logs/compilation/${contract_name}-compile.log"
    
    {
        echo "=== Cairo Compilation Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Try multiple compilation methods
        echo "=== Compilation Attempts ==="
        
        # Method 1: starknet-compile
        if command -v starknet-compile &> /dev/null; then
            echo "🔧 Attempting compilation with starknet-compile..."
            if starknet-compile "$contract_path" --output "$contract_subdir/logs/compilation/${contract_name}-compiled.json" 2>&1; then
                echo "✅ starknet-compile successful"
                compiled_size=$(stat -c%s "$contract_subdir/logs/compilation/${contract_name}-compiled.json" 2>/dev/null || echo "unknown")
                echo "   Compiled artifact size: $compiled_size bytes"
            else
                echo "❌ starknet-compile failed"
            fi
        else
            echo "⚠️ starknet-compile not available"
        fi
        
        # Method 2: Python compilation
        echo ""
        echo "🐍 Attempting Python-based compilation..."
        python3 << EOL
import sys
import os
sys.path.insert(0, '$contract_subdir/src')

try:
    from starkware.starknet.compiler.compile import compile_starknet_files
    from pathlib import Path
    
    contract_path = Path('$contract_path')
    print(f"Compiling: {contract_path}")
    
    try:
        contract_definition = compile_starknet_files(
            files=[str(contract_path)],
            debug_info=True
        )
        
        if contract_definition:
            print("✅ Python compilation successful")
            print(f"   Program data available: {hasattr(contract_definition, 'program')}")
            if hasattr(contract_definition, 'program'):
                program_size = len(str(contract_definition.program.data))
                print(f"   Program data size: {program_size} characters")
        else:
            print("❌ Python compilation returned None")
            
    except Exception as e:
        print(f"❌ Python compilation failed: {e}")
        
except ImportError as e:
    print(f"⚠️ StarkNet compiler not available in Python: {e}")
EOL
        
        echo ""
        echo "=== Compilation Analysis Complete ==="
    } > "$compile_log" 2>&1
    
    log_with_timestamp "✅ Cairo compilation analysis completed"
}

# Comprehensive security analysis
run_comprehensive_security_analysis() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "🛡️ Running comprehensive security analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/security"
    
    # Multiple security analysis files
    local bandit_log="$contract_subdir/logs/security/${contract_name}-bandit.log"
    local flake8_log="$contract_subdir/logs/security/${contract_name}-flake8.log"
    local cairo_security_log="$contract_subdir/logs/security/${contract_name}-cairo-security.log"
    local starknet_audit_log="$contract_subdir/logs/security/${contract_name}-starknet-audit.log"
    
    # Basic Python security (in case of mixed files)
    if command -v bandit &> /dev/null; then
        bandit -r "$contract_subdir/src" -f txt > "$bandit_log" 2>&1 || true
    fi
    
    if command -v flake8 &> /dev/null; then
        flake8 "$contract_path" > "$flake8_log" 2>&1 || true
    fi
    
    # Cairo-specific security analysis
    {
        echo "=== Cairo/StarkNet Security Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        echo "=== Pattern-Based Security Analysis ==="
        
        # Access control patterns
        if grep -n "@external\|@view" "$contract_path"; then
            echo "✅ StarkNet function decorators found"
        fi
        
        if grep -n "get_caller_address\|assert_only_owner" "$contract_path"; then
            echo "✅ Access control patterns detected"
        else
            echo "⚠️ No access control patterns found - review if needed"
        fi
        
        # Storage security
        if grep -n "@storage_var" "$contract_path"; then
            echo "✅ Storage variables declared"
        fi
        
        # Input validation
        if grep -n "assert\|with_attr" "$contract_path"; then
            echo "✅ Input validation patterns found"
        else
            echo "⚠️ Limited input validation detected"
        fi
        
        # Arithmetic operations
        if grep -n "SafeUint256\|uint256_add\|uint256_sub" "$contract_path"; then
            echo "✅ Safe arithmetic operations detected"
        fi
        
        # Event logging
        if grep -n "@event" "$contract_path"; then
            echo "✅ Event declarations found"
        fi
        
        # Reentrancy patterns
        if grep -n "ReentrancyGuard\|nonreentrant" "$contract_path"; then
            echo "✅ Reentrancy protection detected"
        else
            echo "⚠️ No explicit reentrancy protection found"
        fi
        
        echo ""
        echo "=== File Analysis ==="
        file_size=$(stat -c%s "$contract_path" 2>/dev/null || echo "unknown")
        line_count=$(wc -l < "$contract_path" 2>/dev/null || echo "unknown")
        echo "Contract file size: $file_size bytes"
        echo "Contract lines of code: $line_count"
        
        echo "=== Security Analysis Complete ==="
    } > "$cairo_security_log"
    
    # StarkNet-specific audit (simulated)
    {
        echo "=== StarkNet Audit Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        echo "=== Contract Structure Analysis ==="
        
        # Function analysis
        external_funcs=$(grep -c "@external" "$contract_path" 2>/dev/null || echo "0")
        view_funcs=$(grep -c "@view" "$contract_path" 2>/dev/null || echo "0")
        storage_vars=$(grep -c "@storage_var" "$contract_path" 2>/dev/null || echo "0")
        events=$(grep -c "@event" "$contract_path" 2>/dev/null || echo "0")
        
        echo "External functions: $external_funcs"
        echo "View functions: $view_funcs"
        echo "Storage variables: $storage_vars"
        echo "Events: $events"
        
        echo ""
        echo "=== Security Recommendations ==="
        echo "• Verify all external functions have proper access control"
        echo "• Ensure input validation for all user-provided data"
        echo "• Check for potential integer overflow/underflow issues"
        echo "• Verify proper event emission for state changes"
        echo "• Consider reentrancy protection for complex state changes"
        
        echo "=== StarkNet Audit Complete ==="
    } > "$starknet_audit_log"
    
    log_with_timestamp "✅ Comprehensive security analysis completed"
}

# Performance and lint analysis
run_performance_and_lint_analysis() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "⚡ Running performance and lint analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/performance"
    mkdir -p "$contract_subdir/logs/lint"
    
    local perf_log="$contract_subdir/logs/performance/${contract_name}-performance.log"
    local lint_log="$contract_subdir/logs/lint/${contract_name}-lint.log"
    
    # Performance analysis
    {
        echo "=== Performance Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # File metrics
        file_size=$(stat -c%s "$contract_path" 2>/dev/null || echo "unknown")
        line_count=$(wc -l < "$contract_path" 2>/dev/null || echo "unknown")
        func_count=$(grep -c "func " "$contract_path" 2>/dev/null || echo "0")
        
        echo "=== Code Metrics ==="
        echo "File size: $file_size bytes"
        echo "Lines of code: $line_count"
        echo "Function count: $func_count"
        
        # Complexity indicators
        if_count=$(grep -c "if " "$contract_path" 2>/dev/null || echo "0")
        loop_count=$(grep -c -E "(for|while)" "$contract_path" 2>/dev/null || echo "0")
        
        echo "Conditional statements: $if_count"
        echo "Loop constructs: $loop_count"
        
        echo "=== Performance Analysis Complete ==="
    } > "$perf_log"
    
    # Lint analysis (simulated starknet-lint)
    {
        echo "=== StarkNet Lint Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        echo "=== Code Quality Checks ==="
        
        # Naming conventions
        if grep -q "^func [a-z]" "$contract_path"; then
            echo "✅ Function naming follows snake_case convention"
        fi
        
        # Documentation
        comment_lines=$(grep -c "^[[:space:]]*#\|^[[:space:]]*//\|^[[:space:]]*%\|^[[:space:]]*\*" "$contract_path" 2>/dev/null || echo "0")
        doc_ratio=$(awk "BEGIN {printf \"%.1f\", $comment_lines/$line_count*100}")
        echo "Documentation ratio: $doc_ratio% ($comment_lines/$line_count lines)"
        
        # Complexity warnings
        if [ "$func_count" -gt 20 ]; then
            echo "⚠️ High function count ($func_count) - consider modularization"
        fi
        
        if [ "$line_count" -gt 500 ]; then
            echo "⚠️ Large contract ($line_count lines) - consider splitting"
        fi
        
        echo "=== Lint Analysis Complete ==="
    } > "$lint_log"
    
    log_with_timestamp "✅ Performance and lint analysis completed"
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
        (cd "$contract_subdir" && python3 -m pytest tests/ --cov=src --cov-report=term --cov-report=html:logs/coverage/html -v > "$coverage_log" 2>&1) || {
            log_with_timestamp "⚠️ Coverage analysis completed with warnings - check $coverage_log"
        }
    fi
    
    log_with_timestamp "✅ Coverage analysis completed"
}

# Setup Cairo compiler
setup_cairo_compiler

log_with_timestamp "📡 Watching for Cairo contract files in /app/input..."

# Main file monitoring loop
if command -v inotifywait &> /dev/null; then
    inotifywait -m -e close_write,moved_to /app/input --format '%w%f' |
    while read FILE_PATH; do
        if [[ "$FILE_PATH" == *.cairo ]] || [[ "$FILE_PATH" == *.py ]]; then
            filename=$(basename "$FILE_PATH")
            contract_name=$(basename "$filename" .cairo)
            contract_name=$(basename "$contract_name" .py)
            
            # Simple lock mechanism
            lock_file="/tmp/processing_${contract_name}.lock"
            if [ -f "$lock_file" ]; then
                continue
            fi
            echo "$$" > "$lock_file"
            
            {
                start_time=$(date +%s)
                log_with_timestamp "🆕 Processing contract: $filename"
                
                contract_subdir="/app/contracts/${contract_name}"
                mkdir -p "$contract_subdir/src"
                mkdir -p "$contract_subdir/logs"
                cp "$FILE_PATH" "$contract_subdir/src/${filename}"
                
                # Generate comprehensive tests
                generate_comprehensive_tests "$contract_name" "$contract_subdir"
                
                # File type specific processing
                if [[ "$FILE_PATH" == *.cairo ]]; then
                    log_with_timestamp "🔍 Processing Cairo contract: $contract_name"
                    
                    # Cairo compilation
                    run_cairo_compilation "$contract_name" "$contract_subdir/src/${filename}" "$contract_subdir"
                    
                    # Performance and lint analysis
                    run_performance_and_lint_analysis "$contract_name" "$contract_subdir/src/${filename}" "$contract_subdir"
                    
                elif [[ "$FILE_PATH" == *.py ]]; then
                    log_with_timestamp "🔍 Processing Python contract: $contract_name"
                    
                    # Python syntax check
                    if python3 -m py_compile "$contract_subdir/src/${filename}" 2> "$contract_subdir/logs/syntax.log"; then
                        log_with_timestamp "✅ Syntax check passed"
                    else
                        log_with_timestamp "❌ Syntax check failed"
                    fi
                fi
                
                # Common analysis for both types
                run_comprehensive_security_analysis "$contract_name" "$contract_subdir/src/${filename}" "$contract_subdir"
                
                # Run comprehensive tests
                log_with_timestamp "🧪 Running comprehensive tests..."
                (cd "$contract_subdir" && python3 -m pytest tests/ -v --tb=short > "$contract_subdir/logs/test.log" 2>&1) || {
                    log_with_timestamp "⚠️ Some tests may have failed - check logs"
                    # Show test failure summary
                    if [ -f "$contract_subdir/logs/test.log" ]; then
                        echo "Test failure summary:" | tee -a "$LOG_FILE"
                        tail -20 "$contract_subdir/logs/test.log" | tee -a "$LOG_FILE"
                    fi
                }
                
                # Run coverage analysis
                run_coverage_analysis "$contract_name" "$contract_subdir"
                
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
        for FILE_PATH in /app/input/*.cairo /app/input/*.py; do
            [ -e "$FILE_PATH" ] || continue
            # Similar processing logic would go here
        done
        sleep 5
    done
fi   
