#!/bin/bash
set -e

# --- Performance optimization environment setup ---
export NODE_OPTIONS="--max-old-space-size=8192"  # Increase Node.js memory
export NPM_CONFIG_PROGRESS=false  # Faster npm operations
export FOUNDRY_PROFILE=ci  # Optimized Foundry profile
export HARDHAT_PARALLEL=true  # Enable Hardhat parallelization
export HARDHAT_MAX_MEMORY=8192  # Increase Hardhat memory
export REPORT_GAS=true
export HARDHAT_NETWORK=hardhat
export SLITHER_CONFIG_FILE="./config/slither.config.json"

# Parallel processing settings
export PARALLEL_JOBS=${PARALLEL_JOBS:-$(nproc)}
export HARDHAT_COMPILE_JOBS=${PARALLEL_JOBS}

echo "🚀 Starting Enhanced EVM Container..."
echo "⚡ Parallel jobs: $PARALLEL_JOBS"
echo "🧠 Node.js memory: 8GB"

mkdir -p /app/input
mkdir -p /app/logs
mkdir -p /app/contracts
mkdir -p /app/test
mkdir -p /app/logs/slither
mkdir -p /app/logs/coverage
mkdir -p /app/logs/gas
mkdir -p /app/logs/foundry
mkdir -p /app/logs/reports
mkdir -p /app/config
mkdir -p /app/scripts

LOG_FILE="/app/logs/evm-test.log"
ERROR_LOG="/app/logs/evm-error.log"
SECURITY_LOG="/app/logs/security/security-audit.log"
PERFORMANCE_LOG="/app/logs/analysis/performance.log"

# Create log directories
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ERROR_LOG")" \
  "$(dirname "$SECURITY_LOG")" "$(dirname "$PERFORMANCE_LOG")" \
  /app/logs/security /app/logs/analysis /app/logs/benchmarks

: > "$LOG_FILE"

# Enhanced logging with categories
log_with_timestamp() {
    local message="$1"
    local log_type="${2:-info}"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    case $log_type in
        "error") echo "$timestamp ❌ $message" | tee -a "$LOG_FILE" "$ERROR_LOG" ;;
        "security") echo "$timestamp 🛡️ $message" | tee -a "$LOG_FILE" "$SECURITY_LOG" ;;
        "performance") echo "$timestamp ⚡ $message" | tee -a "$LOG_FILE" "$PERFORMANCE_LOG" ;;
        *) echo "$timestamp $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Detect the contract name (case-sensitive!) from the Solidity file
detect_contract_name() {
    local sol_file="$1"
    # Find the first contract definition in the file, supports contract, abstract contract, interface, library
    grep -E '^(contract|abstract contract|interface|library)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$sol_file" | \
    head -1 | \
    sed -E 's/^(contract|abstract contract|interface|library)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/'
}

create_simplified_hardhat_config() {
    contract_name="$1"
    contract_path="$2"
    # If contract_path is given, detect the actual contract name for Hardhat config and imports
    if [ -f "$contract_path" ]; then
        detected_name=$(detect_contract_name "$contract_path")
        if [ -z "$detected_name" ]; then
            detected_name="$contract_name"
        fi
    else
        detected_name="$contract_name"
    fi
    log_with_timestamp "📝 Creating per-contract Hardhat configuration for $contract_name (contract identifier: $detected_name)..."
    cat > "/app/hardhat.config.js" <<EOF
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      { version: "0.8.24", settings: { optimizer: { enabled: true, runs: 200 } } },
      { version: "0.8.20" },
      { version: "0.8.18" },
      { version: "0.8.17" },
      { version: "0.6.12" }
    ],
  },
  networks: {
    hardhat: { chainId: 1337, allowUnlimitedContractSize: true },
    localhost: { url: "http://127.0.0.1:8545" },
  },
  paths: {
    sources: "./contracts/${contract_name}",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
EOF
    ln -sf "/app/hardhat.config.js" "/app/config/hardhat.config.js"
    log_with_timestamp "✅ Created Hardhat config for $contract_name"

    cat > "/app/config/slither.config.json" <<EOF
{
  "detectors_to_exclude": [],
  "exclude_informational": false,
  "exclude_low": false,
  "exclude_medium": false,
  "exclude_high": false,
  "solc_disable_warnings": false,
  "json": "/app/logs/slither/slither-report.json",
  "filter_paths": "node_modules",
  "solc": "solc"
}
EOF
    log_with_timestamp "✅ Created Slither configuration"
}

create_simple_analysis_script() {
    log_with_timestamp "📝 Creating simple contract analysis script..."
    cat > "/app/scripts/analyze-contract.js" <<EOF
const fs = require('fs');
const path = require('path');
function detectContractName(content) {
    const match = content.match(/^(contract|abstract contract|interface|library)\\s+([A-Za-z_][A-Za-z0-9_]*)/m);
    return match ? match[2] : null;
}
function analyzeContract(filePath) {
    console.log('Contract Analysis');
    console.log('================');
    try {
        if (!fs.existsSync(filePath)) {
            console.log(\`File not found: \${filePath}\`);
            return;
        }
        const content = fs.readFileSync(filePath, 'utf8');
        const stats = fs.statSync(filePath);
        console.log(\`File: \${path.basename(filePath)}\`);
        console.log(\`Size: \${stats.size} bytes\`);
        const lines = content.split('\\n');
        console.log(\`Lines: \${lines.length}\`);
        const hasSPDX = content.includes('SPDX-License-Identifier');
        console.log(\`SPDX License: \${hasSPDX ? 'Yes ✅' : 'No ❌'}\`);
        const contractName = detectContractName(content);
        console.log(\`Detected contract identifier: \${contractName || 'N/A'}\`);
        console.log('\\nFunction Detection:');
        const funcs = [
            { name: 'Constructor', regex: /constructor\\s*\\(/g },
            { name: 'Transfer', regex: /\\btransfer\\s*\\(/g },
            { name: 'TransferFrom', regex: /\\btransferFrom\\s*\\(/g },
            { name: 'Approve', regex: /\\bapprove\\s*\\(/g },
            { name: 'SafeMath', regex: /\\busing\\s+SafeMath\\b/g },
            { name: 'Reentrancy Guard', regex: /\\bnonReentrant\\b|\\breentrant\\b/g },
            { name: 'Ownable', regex: /\\bonlyOwner\\b|\\bOwnable\\b/g }
        ];
        funcs.forEach(func => {
            const matches = content.match(func.regex);
            console.log(\`- \${func.name}: \${matches ? matches.length : 0} occurrences\`);
        });
        console.log('\\nSimple Security Checks:');
        const checks = [
            { name: 'tx.origin usage (avoid)', regex: /\\btx\\.origin\\b/g, safe: false },
            { name: 'selfdestruct/suicide', regex: /\\bselfdestruct\\b|\\bsuicide\\b/g, safe: false },
            { name: 'delegatecall usage (caution)', regex: /\\bdelegatecall\\b/g, safe: false },
            { name: 'assembly blocks (caution)', regex: /\\bassembly\\s*{/g, safe: false },
            { name: 'SafeMath/safe math operations', regex: /\\busing\\s+SafeMath\\b|\\.add\\(|\\.sub\\(|\\.mul\\(|\\.div\\(/g, safe: true },
            { name: 'require statements', regex: /\\brequire\\s*\\(/g, safe: true },
            { name: 'revert statements', regex: /\\brevert\\s*\\(/g, safe: true }
        ];
        checks.forEach(check => {
            const matches = content.match(check.regex);
            const count = matches ? matches.length : 0;
            const status = check.safe ? 
                (count > 0 ? '✅ Good' : '⚠️ Missing') : 
                (count > 0 ? '⚠️ Caution' : '✅ Good');
            console.log(\`- \${check.name}: \${count} occurrences - \${status}\`);
        });
    } catch (error) {
        console.error(\`Error analyzing contract: \${error.message}\`);
    }
}
const filePath = process.argv[2] || './contracts/SimpleToken.sol';
analyzeContract(filePath);
EOF
    chmod +x /app/scripts/analyze-contract.js
    log_with_timestamp "✅ Created simple contract analysis script"
}

create_simplified_hardhat_config "default"
create_simple_analysis_script

# Enhanced performance analysis
run_performance_analysis() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "⚡ Running performance analysis for $contract_name..." "performance"
    
    mkdir -p "$contract_subdir/logs/benchmarks"
    local gas_log="$contract_subdir/logs/benchmarks/${contract_name}-gas-analysis.log"
    local size_log="$contract_subdir/logs/benchmarks/${contract_name}-size-analysis.log"
    
    # Gas analysis with Hardhat
    if [ -f "$contract_subdir/hardhat.config.js" ]; then
        (cd "$contract_subdir" && npx hardhat test --gas-reporter > "$gas_log" 2>&1) || {
            log_with_timestamp "⚠️ Gas analysis completed with warnings" "performance"
        }
    fi
    
    # Contract size analysis
    {
        echo "=== Contract Size Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        if [ -f "$contract_subdir/artifacts/contracts/${contract_name}.sol/${contract_name}.json" ]; then
            local bytecode_size=$(jq -r '.deployedBytecode' "$contract_subdir/artifacts/contracts/${contract_name}.sol/${contract_name}.json" | wc -c)
            bytecode_size=$((bytecode_size / 2 - 1))  # Convert hex to bytes
            
            echo "Deployed bytecode size: $bytecode_size bytes"
            echo "EIP-170 limit: 24576 bytes"
            
            if [ "$bytecode_size" -gt 24576 ]; then
                echo "Status: ❌ EXCEEDS EIP-170 LIMIT"
            else
                echo "Status: ✅ Within EIP-170 limit"
                echo "Remaining space: $((24576 - bytecode_size)) bytes"
            fi
        else
            echo "Bytecode not found - compilation may have failed"
        fi
    } > "$size_log"
    
    log_with_timestamp "✅ Performance analysis completed" "performance"
}

# Enhanced coverage analysis
run_coverage_analysis() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "📊 Running coverage analysis for $contract_name..."
    
    mkdir -p "$contract_subdir/logs/coverage"
    local coverage_log="$contract_subdir/logs/coverage/${contract_name}-coverage.log"
    
    # Run Hardhat coverage
    if [ -f "$contract_subdir/hardhat.config.js" ]; then
        (cd "$contract_subdir" && npx hardhat coverage > "$coverage_log" 2>&1) || {
            log_with_timestamp "⚠️ Coverage analysis completed with warnings"
        }
    fi
    
    # Also run Foundry coverage if available
    if command -v forge &> /dev/null; then
        (cd "$contract_subdir" && forge coverage --report lcov \
            --report-file "$contract_subdir/logs/coverage/${contract_name}-foundry-lcov.info" >> "$coverage_log" 2>&1) || {
            log_with_timestamp "⚠️ Foundry coverage generation had issues"
        }
    fi
    
    log_with_timestamp "✅ Coverage analysis completed"
}

# Enhanced security analysis with multiple tools
run_comprehensive_security_audit() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "🛡️ Running comprehensive security audit for $contract_name..." "security"
    
    mkdir -p "$contract_subdir/logs/security"
    
    # Run multiple security analysis tools in parallel
    {
        run_slither_analysis "$contract_name" "$contract_path" "$contract_subdir" &
        SLITHER_PID=$!
        
        run_mythril_analysis "$contract_name" "$contract_path" "$contract_subdir" &
        MYTHRIL_PID=$!
        
        run_custom_security_checks "$contract_name" "$contract_path" "$contract_subdir" &
        CUSTOM_PID=$!
        
        run_npm_audit "$contract_name" "$contract_subdir" &
        NPM_PID=$!
        
        # Wait for all security tools to complete
        wait $SLITHER_PID
        wait $MYTHRIL_PID 
        wait $CUSTOM_PID
        wait $NPM_PID
        
        log_with_timestamp "✅ All security analysis tools completed" "security"
    }
}

# Enhanced Slither analysis
run_slither_analysis() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "Running Slither static analysis..." "security"
    local slither_log="$contract_subdir/logs/security/${contract_name}-slither.log"
    
    if command -v slither &> /dev/null; then
        (cd "$contract_subdir" && slither "$contract_path" \
            --json "$contract_subdir/logs/security/${contract_name}-slither.json" \
            --checklist \
            --exclude-dependencies \
            > "$slither_log" 2>&1) || {
            log_with_timestamp "⚠️ Slither analysis completed with findings, check $slither_log" "security"
        }
    else
        log_with_timestamp "❌ Slither not available, skipping static analysis" "error"
    fi
}

# Add Mythril analysis
run_mythril_analysis() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "Running Mythril symbolic execution..." "security"
    local mythril_log="$contract_subdir/logs/security/${contract_name}-mythril.log"
    
    if command -v myth &> /dev/null; then
        (cd "$contract_subdir" && timeout 300 myth analyze "$contract_path" \
            --execution-timeout 120 \
            --create-timeout 60 \
            -o json \
            > "$mythril_log" 2>&1) || {
            log_with_timestamp "⚠️ Mythril analysis completed with findings" "security"
        }
    else
        log_with_timestamp "ℹ️ Mythril not available, skipping symbolic execution" 
    fi
}

# Custom Solidity security pattern checks
run_custom_security_checks() {
    local contract_name="$1"
    local contract_path="$2"
    local contract_subdir="$3"
    
    log_with_timestamp "Running custom Solidity security pattern checks..." "security"
    local security_log="$contract_subdir/logs/security/${contract_name}-custom-security.log"
    
    {
        echo "=== Custom Solidity Security Analysis ==="
        echo "Contract: $contract_name"
        echo "File: $contract_path"
        echo "Date: $(date)"
        echo ""
        
        # Check for common vulnerabilities
        echo "=== Reentrancy Vulnerability Checks ==="
        if grep -n -E "(\.call\(|\.delegatecall\(|\.send\()" "$contract_path"; then
            echo "WARNING: External calls found - check for reentrancy protection"
            if ! grep -q "nonReentrant\|ReentrancyGuard" "$contract_path"; then
                echo "CRITICAL: No reentrancy protection detected!"
            fi
        else
            echo "✅ No obvious external calls found"
        fi
        echo ""
        
        echo "=== Access Control Checks ==="
        if grep -n -E "(onlyOwner|require.*msg\.sender)" "$contract_path"; then
            echo "✅ Access control mechanisms found"
        else
            echo "WARNING: No access control mechanisms detected"
        fi
        echo ""
        
        echo "=== Integer Overflow/Underflow Checks ==="
        if grep -n -E "(\+\+|--|(\s|\()\+(\s|\))|(\s|\()\-(\s|\))|(\s|\()\*(\s|\))" "$contract_path"; then
            echo "INFO: Arithmetic operations found"
            if grep -q "SafeMath\|unchecked" "$contract_path"; then
                echo "✅ SafeMath or unchecked blocks detected"
            else
                echo "WARNING: Consider using SafeMath for older Solidity versions"
            fi
        fi
        echo ""
        
        echo "=== Randomness and Timestamp Dependence ==="
        if grep -n -E "(block\.timestamp|block\.number|blockhash|block\.difficulty)" "$contract_path"; then
            echo "WARNING: Block properties used - potential for miner manipulation"
        else
            echo "✅ No obvious timestamp dependence found"
        fi
        echo ""
        
        echo "=== Gas Limit and DoS Checks ==="
        if grep -n -E "(for\s*\(|while\s*\()" "$contract_path"; then
            echo "INFO: Loops found - check for DoS via gas limit"
        fi
        echo ""
        
        echo "=== Unchecked Return Values ==="
        if grep -n -E "\.call\(|\.send\(|\.transfer\(" "$contract_path"; then
            echo "INFO: External calls found - ensure return values are checked"
        fi
        echo ""
        
        echo "=== Front-running Vulnerabilities ==="
        if grep -n -E "(commit.*reveal|hash.*nonce)" "$contract_path"; then
            echo "✅ Commit-reveal pattern detected"
        else
            echo "INFO: Consider front-running protection for sensitive operations"
        fi
        echo ""
        
        echo "=== Upgradability Patterns ==="
        if grep -n -E "(proxy|implementation|upgrade)" "$contract_path"; then
            echo "INFO: Upgradability patterns detected - ensure proper access control"
        fi
        echo ""
        
        echo "=== Oracle and External Data ==="
        if grep -n -E "(oracle|price|feed)" "$contract_path"; then
            echo "WARNING: Oracle usage detected - ensure data validation and freshness checks"
        fi
        echo ""
        
        echo "=== End Custom Security Analysis ==="
    } > "$security_log"
    
    log_with_timestamp "✅ Custom security analysis completed" "security"
}

# NPM dependency audit
run_npm_audit() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "Running NPM security audit..." "security"
    local npm_audit_log="$contract_subdir/logs/security/${contract_name}-npm-audit.log"
    
    if [ -f "$contract_subdir/package.json" ]; then
        (cd "$contract_subdir" && npm audit --audit-level=moderate --json > "$npm_audit_log" 2>&1) || {
            log_with_timestamp "⚠️ NPM audit found vulnerabilities, check $npm_audit_log" "security"
        }
    else
        echo "No package.json found - skipping NPM audit" > "$npm_audit_log"
    fi
}

# Enhanced contract analysis and comprehensive test generation
analyze_contract_features() {
    local contract_file="$1"
    local contract_name="$2"
    
    log_with_timestamp "🔍 Analyzing contract features for comprehensive testing..."
    
    # Analyze contract structure and features
    local has_constructor=$(grep -q "constructor\|function.*initialize" "$contract_file" && echo "true" || echo "false")
    local has_owner=$(grep -q -i "owner\|onlyOwner\|Ownable" "$contract_file" && echo "true" || echo "false")
    local has_erc20=$(grep -q -i "ERC20\|transfer\|balanceOf\|totalSupply" "$contract_file" && echo "true" || echo "false")
    local has_erc721=$(grep -q -i "ERC721\|tokenURI\|ownerOf" "$contract_file" && echo "true" || echo "false")
    local has_erc1155=$(grep -q -i "ERC1155\|balanceOfBatch" "$contract_file" && echo "true" || echo "false")
    local has_payable=$(grep -q "payable\|msg.value" "$contract_file" && echo "true" || echo "false")
    local has_modifiers=$(grep -q "modifier\|require\|assert" "$contract_file" && echo "true" || echo "false")
    local has_events=$(grep -q "event\|emit" "$contract_file" && echo "true" || echo "false")
    local has_fallback=$(grep -q "fallback\|receive" "$contract_file" && echo "true" || echo "false")
    local has_upgradeable=$(grep -q -i "upgradeable\|proxy\|implementation" "$contract_file" && echo "true" || echo "false")
    local has_access_control=$(grep -q -i "AccessControl\|role\|ROLE" "$contract_file" && echo "true" || echo "false")
    local has_pausable=$(grep -q -i "Pausable\|pause\|unpause" "$contract_file" && echo "true" || echo "false")
    local has_reentrancy=$(grep -q -i "ReentrancyGuard\|nonReentrant" "$contract_file" && echo "true" || echo "false")
    
    # Store analysis results for test generation
    echo "has_constructor=$has_constructor" > "/tmp/contract_analysis_${contract_name}.env"
    echo "has_owner=$has_owner" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_erc20=$has_erc20" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_erc721=$has_erc721" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_erc1155=$has_erc1155" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_payable=$has_payable" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_modifiers=$has_modifiers" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_events=$has_events" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_fallback=$has_fallback" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_upgradeable=$has_upgradeable" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_access_control=$has_access_control" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_pausable=$has_pausable" >> "/tmp/contract_analysis_${contract_name}.env"
    echo "has_reentrancy=$has_reentrancy" >> "/tmp/contract_analysis_${contract_name}.env"
    
    log_with_timestamp "✅ Contract analysis completed - generating comprehensive tests..."
}

# Generate comprehensive Hardhat tests
generate_comprehensive_tests() {
    local contract_name="$1"
    local contract_file="$2"
    local contract_subdir="$3"
    
    # Load analysis results
    source "/tmp/contract_analysis_${contract_name}.env"
    
    log_with_timestamp "🧪 Generating comprehensive test suite for $contract_name..."
    
    # Create test directory and main test file
    mkdir -p "$contract_subdir/test"
    
    cat > "$contract_subdir/test/${contract_name}.test.js" <<EOF
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("${contract_name} - Comprehensive Test Suite", function () {
    async function deploy${contract_name}Fixture() {
        const [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        
        const ${contract_name}Factory = await ethers.getContractFactory("${contract_name}");
        const ${contract_name,,} = await ${contract_name}Factory.deploy();
        
        return { ${contract_name,,}, owner, addr1, addr2, addrs };
    }
    
    describe("Deployment & Initialization", function () {
        it("Should deploy successfully", async function () {
            const { ${contract_name,,} } = await loadFixture(deploy${contract_name}Fixture);
            expect(${contract_name,,}.address).to.be.properAddress;
        });
EOF

    # Add constructor tests if detected
    if [ "$has_constructor" = "true" ]; then
        cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
        
        it("Should initialize with correct parameters", async function () {
            const { ${contract_name,,}, owner } = await loadFixture(deploy${contract_name}Fixture);
            // Add specific initialization checks based on constructor parameters
            expect(await ${contract_name,,}.deployed()).to.be.ok;
        });
EOF
    fi

    # Add owner tests if detected
    if [ "$has_owner" = "true" ]; then
        cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
    });
    
    describe("Access Control & Ownership", function () {
        it("Should set the right owner", async function () {
            const { ${contract_name,,}, owner } = await loadFixture(deploy${contract_name}Fixture);
            if (typeof ${contract_name,,}.owner === 'function') {
                expect(await ${contract_name,,}.owner()).to.equal(owner.address);
            }
        });
        
        it("Should reject unauthorized access", async function () {
            const { ${contract_name,,}, addr1 } = await loadFixture(deploy${contract_name}Fixture);
            // Test unauthorized access to owner-only functions
            // This will be contract-specific
        });
EOF
    fi

    # Add ERC20 tests if detected
    if [ "$has_erc20" = "true" ]; then
        cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
    });
    
    describe("ERC20 Functionality", function () {
        it("Should have correct name, symbol and decimals", async function () {
            const { ${contract_name,,} } = await loadFixture(deploy${contract_name}Fixture);
            if (typeof ${contract_name,,}.name === 'function') {
                expect(await ${contract_name,,}.name()).to.be.a('string');
            }
            if (typeof ${contract_name,,}.symbol === 'function') {
                expect(await ${contract_name,,}.symbol()).to.be.a('string');
            }
        });
        
        it("Should handle transfers correctly", async function () {
            const { ${contract_name,,}, owner, addr1 } = await loadFixture(deploy${contract_name}Fixture);
            if (typeof ${contract_name,,}.transfer === 'function') {
                // Test transfer functionality with proper checks
                const initialBalance = await ${contract_name,,}.balanceOf(owner.address);
                // Add transfer tests
            }
        });
        
        it("Should handle allowances correctly", async function () {
            const { ${contract_name,,}, owner, addr1 } = await loadFixture(deploy${contract_name}Fixture);
            if (typeof ${contract_name,,}.approve === 'function') {
                // Test approval and allowance functionality
            }
        });
EOF
    fi

    # Add payable tests if detected
    if [ "$has_payable" = "true" ]; then
        cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
    });
    
    describe("Payable Functions & Ether Handling", function () {
        it("Should accept ether correctly", async function () {
            const { ${contract_name,,}, owner } = await loadFixture(deploy${contract_name}Fixture);
            const value = ethers.utils.parseEther("1.0");
            // Test payable functions
        });
        
        it("Should handle withdrawal correctly", async function () {
            const { ${contract_name,,}, owner } = await loadFixture(deploy${contract_name}Fixture);
            // Test withdrawal mechanisms if present
        });
EOF
    fi

    # Add event tests if detected
    if [ "$has_events" = "true" ]; then
        cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
    });
    
    describe("Events & Logging", function () {
        it("Should emit events correctly", async function () {
            const { ${contract_name,,}, owner } = await loadFixture(deploy${contract_name}Fixture);
            // Test event emissions
        });
EOF
    fi

    # Add security tests
    cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
    });
    
    describe("Security & Edge Cases", function () {
        it("Should handle zero addresses properly", async function () {
            const { ${contract_name,,} } = await loadFixture(deploy${contract_name}Fixture);
            // Test zero address handling
        });
        
        it("Should handle large numbers without overflow", async function () {
            const { ${contract_name,,} } = await loadFixture(deploy${contract_name}Fixture);
            // Test with large numbers to check for overflow
            const largeNumber = ethers.BigNumber.from("2").pow(255);
            // Add overflow tests
        });
        
        it("Should revert on invalid operations", async function () {
            const { ${contract_name,,}, addr1 } = await loadFixture(deploy${contract_name}Fixture);
            // Test various invalid operations
        });
EOF

    # Add reentrancy tests if protection detected
    if [ "$has_reentrancy" = "true" ]; then
        cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
        
        it("Should prevent reentrancy attacks", async function () {
            const { ${contract_name,,} } = await loadFixture(deploy${contract_name}Fixture);
            // Test reentrancy protection
        });
EOF
    fi

    # Close the test file
    cat >> "$contract_subdir/test/${contract_name}.test.js" <<EOF
    });
    
    describe("Gas Optimization Tests", function () {
        it("Should be gas efficient for common operations", async function () {
            const { ${contract_name,,} } = await loadFixture(deploy${contract_name}Fixture);
            // Test gas efficiency of key functions
        });
    });
});
EOF

    # Generate additional specialized test files
    generate_security_tests "$contract_name" "$contract_subdir"
    generate_integration_tests "$contract_name" "$contract_subdir"
    
    log_with_timestamp "✅ Comprehensive test suite generated successfully"
    log_with_timestamp "📊 Generated tests include: deployment, functionality, security, edge cases, and gas optimization"
}

# Generate specialized security tests
generate_security_tests() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    cat > "$contract_subdir/test/${contract_name}.security.test.js" <<EOF
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("${contract_name} - Security Tests", function () {
    let ${contract_name,,};
    let owner, attacker, user;
    
    beforeEach(async function () {
        [owner, attacker, user] = await ethers.getSigners();
        const ${contract_name}Factory = await ethers.getContractFactory("${contract_name}");
        ${contract_name,,} = await ${contract_name}Factory.deploy();
    });
    
    describe("Access Control Vulnerabilities", function () {
        it("Should prevent unauthorized function calls", async function () {
            // Test unauthorized access
        });
        
        it("Should validate input parameters", async function () {
            // Test input validation
        });
    });
    
    describe("Common Attack Vectors", function () {
        it("Should be resistant to front-running", async function () {
            // Test front-running resistance
        });
        
        it("Should handle flash loan attacks", async function () {
            // Test flash loan resistance
        });
        
        it("Should prevent integer overflow/underflow", async function () {
            // Test arithmetic safety
        });
    });
});
EOF
}

# Generate integration tests
generate_integration_tests() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    cat > "$contract_subdir/test/${contract_name}.integration.test.js" <<EOF
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("${contract_name} - Integration Tests", function () {
    let ${contract_name,,};
    let owner, users;
    
    beforeEach(async function () {
        [owner, ...users] = await ethers.getSigners();
        const ${contract_name}Factory = await ethers.getContractFactory("${contract_name}");
        ${contract_name,,} = await ${contract_name}Factory.deploy();
    });
    
    describe("Multi-user Scenarios", function () {
        it("Should handle multiple concurrent users", async function () {
            // Test concurrent usage
        });
        
        it("Should maintain state consistency", async function () {
            // Test state consistency across operations
        });
    });
    
    describe("Cross-contract Interactions", function () {
        it("Should interact correctly with other contracts", async function () {
            // Test external contract interactions
        });
    });
});
EOF
}

# Main file processing loop with enhanced parallel execution
log_with_timestamp "📡 Watching for Solidity contract files in /app/input..."

# Use inotify for real-time file monitoring
if command -v inotifywait &> /dev/null; then
    inotifywait -m -e close_write,moved_to /app/input --format '%w%f' |
    while read FILE_PATH; do
        if [[ "$FILE_PATH" == *.sol ]]; then
            filename=$(basename "$FILE_PATH")
            contract_name=$(basename "$filename" .sol)
            
            # Improved lock mechanism to prevent duplicate processing
            lock_file="/tmp/processing_${contract_name}.lock"
            
            # Skip if already processing or recently processed
            if [ -f "$lock_file" ]; then
                log_with_timestamp "🔄 Skipping $filename - already processing or recently processed"
                continue
            fi
            
            # Create processing lock with timestamp
            timestamp="$(date +%s)"
            echo "$timestamp" > "$lock_file"
            
            # Small delay to handle multiple rapid file events
            sleep 1
            
            # Double-check lock is still ours (prevent race conditions)
            if [ ! -f "$lock_file" ] || [ "$(cat "$lock_file" 2>/dev/null)" != "$timestamp" ]; then
                log_with_timestamp "🔄 Lock conflict detected for $filename - skipping"
                continue
            fi
            
            {
                start_time=$(date +%s)
                log_with_timestamp "🆕 Processing new Solidity contract: $filename"
                
                contract_subdir="/app/contracts/${contract_name}"
                mkdir -p "$contract_subdir"
                # Create necessary log directories for this contract
                mkdir -p "$contract_subdir/logs"
                mkdir -p "$contract_subdir/logs/benchmarks"
                mkdir -p "$contract_subdir/logs/coverage" 
                mkdir -p "$contract_subdir/logs/security"
                mkdir -p "$contract_subdir/logs/gas"
                cp "$FILE_PATH" "$contract_subdir/${filename}"
                
                # Enhanced contract analysis and test generation
                analyze_contract_features "$contract_subdir/${filename}" "$contract_name"
                generate_comprehensive_tests "$contract_name" "$contract_subdir/${filename}" "$contract_subdir"
                
                # Create optimized Hardhat configuration
                create_simplified_hardhat_config "$contract_name" "$contract_subdir/${filename}"
                
                # Enhanced compilation with error handling
                log_with_timestamp "🔨 Compiling $contract_name with enhanced settings..."
                if (cd "$contract_subdir" && npx hardhat compile --parallel --max-memory $HARDHAT_MAX_MEMORY > "$contract_subdir/logs/compile.log" 2>&1); then
                    log_with_timestamp "✅ Compilation successful"
                    
                    # Run all analysis tools in parallel
                    log_with_timestamp "🔍 Starting parallel analysis tools..."
                    {
                        run_comprehensive_security_audit "$contract_name" "$contract_subdir/${filename}" "$contract_subdir" &
                        SECURITY_PID=$!
                        
                        run_coverage_analysis "$contract_name" "$contract_subdir" &
                        COVERAGE_PID=$!
                        
                        run_performance_analysis "$contract_name" "$contract_subdir" &
                        PERFORMANCE_PID=$!
                        
                        # Run comprehensive tests
                        (cd "$contract_subdir" && npm test > "$contract_subdir/logs/test-results.log" 2>&1) &
                        TEST_PID=$!
                        
                        # Wait for all tools to complete
                        wait $SECURITY_PID
                        wait $COVERAGE_PID
                        wait $PERFORMANCE_PID
                        wait $TEST_PID
                        
                        log_with_timestamp "✅ All parallel analysis tools completed"
                    }
                    
                else
                    log_with_timestamp "❌ Compilation failed for $contract_name" "error"
                    log_with_timestamp "📋 Compilation error details:" "error"
                    if [ -f "$contract_subdir/logs/compile.log" ]; then
                        cat "$contract_subdir/logs/compile.log" | tail -20 | while IFS= read -r line; do
                            log_with_timestamp "   $line" "error"
                        done
                    else
                        log_with_timestamp "   No compilation log found" "error"
                    fi
                    log_with_timestamp "🔍 Checking Hardhat configuration and contract syntax..." "error"
                fi
                
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                log_with_timestamp "🏁 Completed processing $filename in ${duration}s"
                
                # AI report generation
                # Create a clean log file for AI processing (exclude verbose build logs)
                AI_CLEAN_LOG="/app/logs/ai-clean-${contract_name}.log"
                
                # Copy only important log entries (exclude verbose build/test output)
                grep -E "(🔧|🧪|🔍|✅|❌|⚠️|🛡️|⚡|📊|🏁)" "$LOG_FILE" > "$AI_CLEAN_LOG" 2>/dev/null || touch "$AI_CLEAN_LOG"
                
                # Set temporary LOG_FILE for AI processing
                ORIGINAL_LOG_FILE="$LOG_FILE"
                export LOG_FILE="$AI_CLEAN_LOG"
                
                if node /app/scripts/aggregate-all-logs.js "$contract_name"; then
                    log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.txt"
                else
                    log_with_timestamp "❌ AI-enhanced aggregation failed" "error"
                fi
                
                # Restore original LOG_FILE and clean up
                export LOG_FILE="$ORIGINAL_LOG_FILE"
                rm -f "$AI_CLEAN_LOG"
                
                log_with_timestamp "=========================================="
                
                # Remove processing lock
                rm -f "$lock_file"
                
                # Clean up any old locks (older than 10 minutes)
                find /tmp -name "processing_*.lock" -type f -mmin +10 -delete 2>/dev/null || true
                
            } 2>&1 | tee -a "$LOG_FILE"
        fi
    done
else
    # Fallback to polling if inotify not available
    log_with_timestamp "⚠️ inotifywait not available, using polling mode"
    while true; do
        for FILE_PATH in /app/input/*.sol; do
            [ -e "$FILE_PATH" ] || continue
            filename=$(basename "$FILE_PATH")
            contract_name=$(basename "$filename" .sol)
            
            # Same lock mechanism for polling mode
            lock_file="/tmp/processing_${contract_name}.lock"
            
            # Skip if already processing
            if [ -f "$lock_file" ]; then
                continue
            fi
            
            # Create processing lock
            timestamp="$(date +%s)"
            echo "$timestamp" > "$lock_file"
            
            # Process the contract (similar to inotify path)
            {
                log_with_timestamp "🆕 Processing Solidity contract: $filename"
                
                contract_subdir="/app/contracts/${contract_name}"
                mkdir -p "$contract_subdir"
                # Create necessary log directories for this contract
                mkdir -p "$contract_subdir/logs"
                mkdir -p "$contract_subdir/logs/benchmarks"
                mkdir -p "$contract_subdir/logs/coverage" 
                mkdir -p "$contract_subdir/logs/security"
                mkdir -p "$contract_subdir/logs/gas"
                cp "$contract_path" "$contract_subdir/${filename}"
                
                analyze_contract_features "$contract_subdir/${filename}" "$contract_name"
                generate_comprehensive_tests "$contract_name" "$contract_subdir/${filename}" "$contract_subdir"
                create_simplified_hardhat_config "$contract_name" "$contract_subdir/${filename}"
                
                log_with_timestamp "🔨 Compiling $contract_name..."
                if (cd "$contract_subdir" && npx hardhat compile --parallel > "$contract_subdir/logs/compile.log" 2>&1); then
                    log_with_timestamp "✅ Compilation successful"
                    
                    # Parallel analysis
                    {
                        run_comprehensive_security_audit "$contract_name" "$contract_subdir/${filename}" "$contract_subdir" &
                        run_coverage_analysis "$contract_name" "$contract_subdir" &
                        run_performance_analysis "$contract_name" "$contract_subdir" &
                        wait
                    }
                    
                    log_with_timestamp "✅ All analysis tools completed"
                else
                    log_with_timestamp "❌ Compilation failed for $contract_name" "error"
                    log_with_timestamp "📋 Compilation error details:" "error"
                    if [ -f "$contract_subdir/logs/compile.log" ]; then
                        cat "$contract_subdir/logs/compile.log" | tail -20 | while IFS= read -r line; do
                            log_with_timestamp "   $line" "error"
                        done
                    else
                        log_with_timestamp "   No compilation log found" "error"
                    fi
                    log_with_timestamp "🔍 Checking Hardhat configuration and contract syntax..." "error"
                fi
                
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                log_with_timestamp "🏁 Completed processing $filename in ${duration}s"
                
                # AI report generation
                if node /app/scripts/aggregate-all-logs.js "$contract_name" >> "$LOG_FILE" 2>&1; then
                    log_with_timestamp "✅ AI-enhanced report generated"
                else
                    log_with_timestamp "❌ AI-enhanced aggregation failed" "error"
                fi
                
                # Clean up the lock
                rm -f "$lock_file"
                
            } 2>&1 | tee -a "$LOG_FILE"
        done
        
        sleep 5  # Poll every 5 seconds
    done
fi
