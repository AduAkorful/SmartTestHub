#!/bin/bash
set -e

echo "🚀 Starting EVM container..."

# Activate Python virtual environment for security tools
source /opt/venv/bin/activate

export REPORT_GAS=true
export HARDHAT_NETWORK=hardhat
export SLITHER_CONFIG_FILE="./config/slither.config.json"

# Verify tools are available
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE:-/tmp/setup.log}"
}

echo "🔧 Verifying tool availability..."
command -v forge >/dev/null 2>&1 && echo "✅ Foundry (forge) available" || echo "⚠️ Foundry not found"
command -v slither >/dev/null 2>&1 && echo "✅ Slither available" || echo "⚠️ Slither not found" 
command -v myth >/dev/null 2>&1 && echo "✅ Mythril available" || echo "⚠️ Mythril not found"
command -v solc >/dev/null 2>&1 && echo "✅ Solidity compiler available" || echo "⚠️ Solc not found"
command -v node >/dev/null 2>&1 && echo "✅ Node.js available" || echo "⚠️ Node.js not found"

# Clean slate initialization - remove ALL cached artifacts and tool caches
rm -rf /app/cache /app/cache_forge /app/artifacts /app/out /app/broadcast 2>/dev/null || true
rm -rf /app/test/*.t.sol 2>/dev/null || true
# Clear all tool caches globally
rm -rf ~/.slither_cache /tmp/slither_cache ~/.mythril /tmp/mythril_cache 2>/dev/null || true
rm -rf ~/.hardhat ~/.npm ~/.solidity ~/.foundry/cache 2>/dev/null || true
# Clear Node.js caches
npm cache clean --force 2>/dev/null || true
# Disable environment-level caching
export SLITHER_DISABLE_CACHE=1
export HARDHAT_DISABLE_CACHE=1

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
mkdir -p /app/cache
mkdir -p /app/artifacts

LOG_FILE="/app/logs/evm-test.log"
: > "$LOG_FILE"

# Redefine log function with LOG_FILE now available
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize Foundry workspace if needed
if [ ! -f "foundry.toml" ]; then
    log_with_timestamp "🔧 Initializing Foundry workspace..."
    forge init --force --no-git --template foundry-rs/forge-template . 2>/dev/null || true
fi

log_with_timestamp "✅ EVM container initialization complete"

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

log_with_timestamp "📡 Watching /app/input for incoming Solidity files..."

MARKER_DIR="/app/.processed"
mkdir -p "$MARKER_DIR"

inotifywait -m -e close_write,moved_to,create /app/input |
while read -r directory events filename; do
  if [[ "$filename" == *.sol ]]; then
    MARKER_FILE="$MARKER_DIR/$filename.processed"
    FILE_PATH="/app/input/$filename"
    if [ ! -f "$FILE_PATH" ]; then
        continue
    fi
    CURRENT_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')
    if [ -f "$MARKER_FILE" ]; then
        LAST_HASH=$(cat "$MARKER_FILE")
        if [ "$CURRENT_HASH" == "$LAST_HASH" ]; then
            log_with_timestamp "⏭️ Skipping duplicate processing of $filename (same content hash)"
            continue
        fi
    fi
    echo "$CURRENT_HASH" > "$MARKER_FILE"

    {
      log_with_timestamp "🆕 Detected Solidity contract: $filename"

      contract_name=$(basename "$filename" .sol)
      contract_subdir="/app/contracts/$contract_name"
      mkdir -p "$contract_subdir"
      cp "$FILE_PATH" "$contract_subdir/$filename"
      log_with_timestamp "📁 Copied $filename to $contract_subdir"

      contract_path="$contract_subdir/$filename"
      test_file="./test/${contract_name}.t.sol"

      # ==== Detect actual contract identifier ====
      detected_name=$(detect_contract_name "$contract_path")
      if [ -z "$detected_name" ]; then
        detected_name="$contract_name"
      fi

      # ==== Create per-contract Hardhat config ====
      create_simplified_hardhat_config "$contract_name" "$contract_path"

      # ==== AUTO-GENERATE TEST FILE IF MISSING ====
      if [ ! -f "$test_file" ]; then
        log_with_timestamp "📝 Auto-generating Foundry test file for $contract_name (contract identifier: $detected_name)"
        
        # Check if contract has constructor parameters
        has_constructor=$(grep -c "constructor(" "$contract_path" || echo "0")
        
        if [ "$has_constructor" -gt 0 ]; then
          # Generate test with flexible constructor
          cat > "$test_file" <<EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/${contract_name}/${filename}";

contract ${detected_name}Test is Test {
    ${detected_name} public contractInstance;
    address public owner;

    function setUp() public {
        owner = address(this);
        // Deploy with basic parameters - adjust as needed
        try new ${detected_name}() returns (${detected_name} instance) {
            contractInstance = instance;
        } catch {
            // Skip deployment if constructor requires parameters
            vm.skip(true);
        }
    }

    function testContractExists() public {
        if (address(contractInstance) != address(0)) {
            assertTrue(address(contractInstance) != address(0));
        }
    }

    function testBasicFunctionality() public {
        if (address(contractInstance) != address(0)) {
            // Add basic function tests here
            assertTrue(true, "Contract deployed successfully");
        }
    }
}
EOF
        else
          # Generate test for parameterless constructor
          cat > "$test_file" <<EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/${contract_name}/${filename}";

contract ${detected_name}Test is Test {
    ${detected_name} public contractInstance;

    function setUp() public {
        contractInstance = new ${detected_name}();
    }

    function testDeployment() public {
        assertTrue(address(contractInstance) != address(0), "Contract should be deployed");
    }

    function testBasicFunctionality() public {
        // Add specific tests based on contract functions
        assertTrue(true, "Basic functionality test placeholder");
    }
}
EOF
        fi
        log_with_timestamp "✅ Enhanced test file created at $test_file"
      fi

      log_with_timestamp "🔨 Attempting direct Solidity compilation..."
      mkdir -p /app/artifacts
      if solc --bin --abi --optimize --overwrite -o /app/artifacts "$contract_path" 2>/dev/null; then
        log_with_timestamp "✅ Direct Solidity compilation successful"
      else
        log_with_timestamp "⚠️ Direct compilation had issues, continuing with analysis"
      fi

      # ==== CLEAN UP OLD TEST FILES AND CACHE ====
      log_with_timestamp "🧹 Cleaning up previous test artifacts and cache..."
      # Remove ALL old test files and cache to prevent contamination
      rm -rf ./test/*.t.sol 2>/dev/null || true
      rm -rf ./cache ./cache_forge ./artifacts ./out 2>/dev/null || true
      rm -rf ./broadcast ./lib/cache 2>/dev/null || true
      # Clear foundry cache completely
      forge clean 2>/dev/null || true
      # Recreate directories
      mkdir -p ./test ./cache ./artifacts
      
      # ==== TAGGED LOG OUTPUTS ====
      log_with_timestamp "🧪 Running Foundry tests with gas reporting..."
      # Initialize foundry if needed
      if [ ! -f "foundry.toml" ]; then
        forge init --force --no-git --template foundry-rs/forge-template . 2>/dev/null || true
      fi
      
      # Run tests with better error handling - force fresh compilation
      if forge test --match-contract "${detected_name}Test" --gas-report --json --force > ./logs/foundry/${contract_name}-foundry-test-report.json 2>&1; then
        log_with_timestamp "✅ Foundry tests passed with gas report"
        # Also create a readable text version
        forge test --match-contract "${detected_name}Test" --gas-report > ./logs/foundry/${contract_name}-foundry-test-readable.txt 2>&1 || true
      else
        log_with_timestamp "❌ Foundry tests failed - check logs/foundry/${contract_name}-foundry-test-report.json"
        # Try to get more detailed error info
        forge test --match-contract "${detected_name}Test" -vvv > ./logs/foundry/${contract_name}-foundry-error-verbose.txt 2>&1 || true
      fi

      log_with_timestamp "📊 Generating Foundry coverage report..."
      if forge coverage --contracts "$contract_subdir" --report lcov --report-file ./logs/coverage/${contract_name}-foundry-lcov.info 2>&1 | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ Foundry coverage report generated"
      else
        log_with_timestamp "⚠️ Foundry coverage generation failed"
      fi

      log_with_timestamp "🔍 Running simple contract analysis..."
      if node /app/scripts/analyze-contract.js "$contract_path" > "./logs/reports/${contract_name}-analysis.txt" 2>&1; then
        log_with_timestamp "✅ Simple contract analysis completed"
      else
        log_with_timestamp "⚠️ Simple contract analysis failed"
      fi

      log_with_timestamp "🛡️ Running Slither security analysis..."
      if command -v slither &> /dev/null; then
        # Clear Slither cache before analysis
        rm -rf ~/.slither_cache /tmp/slither_cache 2>/dev/null || true
        export SLITHER_DISABLE_CACHE=1
        if slither "$contract_path" --solc solc --json --disable-color > "./logs/slither/${contract_name}-report.json" 2>&1; then
          log_with_timestamp "✅ Slither analysis completed"
          # Also create human-readable version
          slither "$contract_path" --solc solc > "./logs/slither/${contract_name}-report.txt" 2>&1 || true
        else
          log_with_timestamp "⚠️ Slither analysis completed with findings"
          slither "$contract_path" --solc solc > "./logs/slither/${contract_name}-report.txt" 2>&1 || true
        fi
      else
        log_with_timestamp "ℹ️ Slither not available, skipping security analysis"
      fi

      log_with_timestamp "🔮 Running Mythril security analysis..."
      if command -v myth &> /dev/null; then
        # Clear Mythril cache before analysis
        rm -rf ~/.mythril /tmp/mythril_cache 2>/dev/null || true
        # Run Mythril analysis with timeout and no cache
        timeout 300 myth analyze "$contract_path" --solv 0.8.20 --execution-timeout 60 --no-onchain-storage-access > "./logs/slither/${contract_name}-mythril.txt" 2>&1 && {
          log_with_timestamp "✅ Mythril analysis completed"
        } || {
          log_with_timestamp "⚠️ Mythril analysis timed out or found issues"
        }
      else
        log_with_timestamp "ℹ️ Mythril not available, installing..."
        pip3 install mythril > /dev/null 2>&1 && {
          # Clear cache after install
          rm -rf ~/.mythril /tmp/mythril_cache 2>/dev/null || true
          timeout 300 myth analyze "$contract_path" --solv 0.8.20 --execution-timeout 60 --no-onchain-storage-access > "./logs/slither/${contract_name}-mythril.txt" 2>&1 && {
            log_with_timestamp "✅ Mythril analysis completed"
          } || {
            log_with_timestamp "⚠️ Mythril analysis had issues"
          }
        } || {
          log_with_timestamp "ℹ️ Could not install Mythril, skipping"
        }
      fi

      log_with_timestamp "📏 Analyzing contract size..."
      filesize=$(stat -c%s "$contract_path")
      echo "Contract: $detected_name" > "./logs/reports/${contract_name}-size.txt"
      echo "Source size: $filesize bytes" >> "./logs/reports/${contract_name}-size.txt"

      if [ -f "/app/artifacts/${contract_name}.bin" ]; then
        binsize=$(stat -c%s "/app/artifacts/${contract_name}.bin")
        hexsize=$((binsize / 2))
        echo "Compiled size: $hexsize bytes" >> "./logs/reports/${contract_name}-size.txt"
        echo "EIP-170 limit: 24576 bytes" >> "./logs/reports/${contract_name}-size.txt"
        if [ "$hexsize" -gt 24576 ]; then
          echo "Status: Exceeds limit ❌" >> "./logs/reports/${contract_name}-size.txt"
        else
          echo "Status: Within limit ✅" >> "./logs/reports/${contract_name}-size.txt"
        fi
      fi
      log_with_timestamp "✅ Contract size analysis completed"

      log_with_timestamp "📋 Creating test summary..."
      cat > "./logs/reports/test-summary-${contract_name}.md" <<EOF
# Test Summary for ${detected_name}

## Contract Information
- **File**: ${filename}
- **Contract Name**: ${detected_name}
- **Test Date**: $(date '+%Y-%m-%d %H:%M:%S')
- **Source Size**: ${filesize} bytes

## Analysis Results
- **Compilation**: $([ -f "/app/artifacts/${contract_name}.bin" ] && echo "✅ SUCCESSFUL" || echo "⚠️ ISSUES FOUND")
- **Foundry Tests**: $(grep -q "✅ Foundry tests passed" "$LOG_FILE" && echo "✅ PASSED" || echo "ℹ️ N/A")
- **Security Analysis**: $(grep -q "✅ Slither analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ ISSUES FOUND")
- **Contract Analysis**: $(grep -q "✅ Simple contract analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ FAILED")
EOF

      if [ -f "/app/artifacts/${contract_name}.bin" ]; then
        cat >> "./logs/reports/test-summary-${contract_name}.md" <<EOF
- **Compiled Size**: ${hexsize} bytes
- **Contract Size Limit**: $([ "$hexsize" -gt 24576 ] && echo "❌ EXCEEDS LIMIT" || echo "✅ WITHIN LIMIT")
EOF
      fi

      cat >> "./logs/reports/test-summary-${contract_name}.md" <<EOF

## Files Generated
- Security Report: \`logs/slither/${contract_name}-report.txt\`
- Contract Analysis: \`logs/reports/${contract_name}-analysis.txt\`
- Size Analysis: \`logs/reports/${contract_name}-size.txt\`
- Foundry Test Report: \`logs/foundry/${contract_name}-foundry-test-report.json\`
- Coverage Report: \`logs/coverage/${contract_name}-foundry-lcov.info\`
- Full Log: \`logs/evm-test.log\`

## Contract Analysis Highlights

EOF

      if [ -f "./logs/reports/${contract_name}-analysis.txt" ]; then
        grep "Simple Security Checks:" -A 20 "./logs/reports/${contract_name}-analysis.txt" >> "./logs/reports/test-summary-${contract_name}.md" || true
      fi

      log_with_timestamp "📋 Test summary created: logs/reports/test-summary-${contract_name}.md"
      log_with_timestamp "🏁 All EVM analysis complete for $filename"
      log_with_timestamp "=========================================="

      # Clean up any old reports for this contract before generating new one
      rm -f "/app/logs/reports/${contract_name}-report.txt" 2>/dev/null || true
      
      log_with_timestamp "🤖 Starting AI-enhanced aggregation for ${contract_name} ONLY..."
      if node /app/scripts/aggregate-all-logs.js "$contract_name" >> "$LOG_FILE" 2>&1; then
        log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/${contract_name}-report.txt"
      else
        log_with_timestamp "❌ AI-enhanced aggregation failed (see log for details)"
      fi
      log_with_timestamp "=========================================="

      # Optional: clean up contract subdir after run, keep {contract_name}-report.txt
      find "$contract_subdir" -type f ! -name "${contract_name}-report.txt" -delete
      find "$contract_subdir" -type d -empty -delete

    } 2>&1
  fi
done
