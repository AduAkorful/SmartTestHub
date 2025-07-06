#!/bin/bash
set -e

echo "🚀 Starting EVM container..."

# Set environment variables for better integration
export REPORT_GAS=true
export HARDHAT_NETWORK=hardhat
export SLITHER_CONFIG_FILE="./config/slither.config.json"

# Ensure required folders exist
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

# Clear old log (or comment this line if you prefer appending)
: > "$LOG_FILE"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create a simplified hardhat config that doesn't rely on toolbox
create_simplified_hardhat_config() {
    log_with_timestamp "📝 Creating simplified Hardhat configuration..."
    cat > "/app/hardhat.config.js" <<EOF
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.20",
      },
      {
        version: "0.8.18",
      },
      {
        version: "0.8.17",
      },
      {
        version: "0.6.12",
      },
    ],
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
EOF
    # Create a symbolic link in config directory if needed
    ln -sf "/app/hardhat.config.js" "/app/config/hardhat.config.js"
    log_with_timestamp "✅ Created simplified Hardhat configuration"
    
    # Create Slither config
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

# Create simple contract analysis script without hardhat dependencies
create_simple_analysis_script() {
    log_with_timestamp "📝 Creating simple contract analysis script..."
    cat > "/app/scripts/analyze-contract.js" <<EOF
const fs = require('fs');
const path = require('path');

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
        
        // Basic info
        console.log(\`File: \${path.basename(filePath)}\`);
        console.log(\`Size: \${stats.size} bytes\`);
        
        // Count lines
        const lines = content.split('\\n');
        console.log(\`Lines: \${lines.length}\`);
        
        // Check for SPDX license
        const hasSPDX = content.includes('SPDX-License-Identifier');
        console.log(\`SPDX License: \${hasSPDX ? 'Yes ✅' : 'No ❌'}\`);
        
        // Check for common function signatures
        console.log('\\nFunction Detection:');
        const funcs = [
            { name: 'Constructor', regex: /constructor\s*\(/g },
            { name: 'Transfer', regex: /\btransfer\s*\(/g },
            { name: 'TransferFrom', regex: /\btransferFrom\s*\(/g },
            { name: 'Approve', regex: /\bapprove\s*\(/g },
            { name: 'SafeMath', regex: /\busing\s+SafeMath\b/g },
            { name: 'Reentrancy Guard', regex: /\bnonReentrant\b|\breentrant\b/g },
            { name: 'Ownable', regex: /\bonlyOwner\b|\bOwnable\b/g }
        ];
        
        funcs.forEach(func => {
            const matches = content.match(func.regex);
            console.log(\`- \${func.name}: \${matches ? matches.length : 0} occurrences\`);
        });
        
        // Simple security check
        console.log('\\nSimple Security Checks:');
        
        // Check for common vulnerabilities
        const checks = [
            { name: 'tx.origin usage (avoid)', regex: /\btx\.origin\b/g, safe: false },
            { name: 'selfdestruct/suicide', regex: /\bselfdestruct\b|\bsuicide\b/g, safe: false },
            { name: 'delegatecall usage (caution)', regex: /\bdelegatecall\b/g, safe: false },
            { name: 'assembly blocks (caution)', regex: /\bassembly\s*{/g, safe: false },
            { name: 'SafeMath/safe math operations', regex: /\busing\s+SafeMath\b|\.add\(|\.sub\(|\.mul\(|\.div\(/g, safe: true },
            { name: 'require statements', regex: /\brequire\s*\(/g, safe: true },
            { name: 'revert statements', regex: /\brevert\s*\(/g, safe: true }
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

// Get file path from command line or use default
const filePath = process.argv[2] || './contracts/SimpleToken.sol';
analyzeContract(filePath);
EOF
    chmod +x /app/scripts/analyze-contract.js
    log_with_timestamp "✅ Created simple contract analysis script"
}

# Create simplified configuration
create_simplified_hardhat_config
create_simple_analysis_script

# Watch the input folder where backend will drop .sol files
log_with_timestamp "📡 Watching /app/input for incoming Solidity files..."

# Use a marker file to prevent duplicate processing
MARKER_DIR="/app/.processed"
mkdir -p "$MARKER_DIR"

inotifywait -m -e close_write,moved_to,create /app/input |
while read -r directory events filename; do
  if [[ "$filename" == *.sol ]]; then
    # Check if file was already processed (prevent duplicates)
    MARKER_FILE="$MARKER_DIR/$filename.processed"
    if [ -f "$MARKER_FILE" ]; then
        LAST_PROCESSED=$(cat "$MARKER_FILE")
        CURRENT_TIME=$(date +%s)
        # Only process if last processed more than 30 seconds ago
        if (( $CURRENT_TIME - $LAST_PROCESSED < 30 )); then
            log_with_timestamp "⏭️ Skipping duplicate processing of $filename (processed ${LAST_PROCESSED}s ago)"
            continue
        fi
    fi
    
    {
      # Mark file as processed with timestamp
      date +%s > "$MARKER_FILE"
      
      log_with_timestamp "🆕 Detected Solidity contract: $filename"

      # Move file to /app/contracts (overwrite if same name exists)
      mkdir -p /app/contracts
      cp "/app/input/$filename" "/app/contracts/$filename"
      log_with_timestamp "📁 Copied $filename to contracts directory"

      # Extract contract name for better reporting
      contract_name=$(basename "$filename" .sol)
      contract_path="/app/contracts/$filename"
      
      # Try to compile with solc directly
      log_with_timestamp "🔨 Attempting direct Solidity compilation..."
      mkdir -p /app/artifacts
      if solc --bin --abi --optimize --overwrite -o /app/artifacts /app/contracts/$filename 2>/dev/null; then
        log_with_timestamp "✅ Direct Solidity compilation successful"
      else
        log_with_timestamp "⚠️ Direct compilation had issues, continuing with analysis"
      fi
      
      # Run Foundry tests if any .t.sol files exist
      if compgen -G './test/*.t.sol' > /dev/null 2>&1; then
        log_with_timestamp "🧪 Running Foundry tests with gas reporting..."
        if forge test --gas-report --json > ./logs/foundry/foundry-test-report.json 2>&1 | tee -a "$LOG_FILE"; then
          log_with_timestamp "✅ Foundry tests passed with gas report"
        else
          log_with_timestamp "❌ Foundry tests failed - check logs/foundry/foundry-test-report.json"
        fi
        
        # Generate forge coverage
        log_with_timestamp "📊 Generating Foundry coverage report..."
        if forge coverage --report lcov --report-file ./logs/coverage/foundry-lcov.info 2>&1 | tee -a "$LOG_FILE"; then
          log_with_timestamp "✅ Foundry coverage report generated"
        else
          log_with_timestamp "⚠️ Foundry coverage generation failed"
        fi
      else
        log_with_timestamp "ℹ️ No Foundry test files found, skipping forge test"
      fi

      # Run simple static analysis with our script
      log_with_timestamp "🔍 Running simple contract analysis..."
      if node /app/scripts/analyze-contract.js "$contract_path" > "./logs/reports/${contract_name}-analysis.txt" 2>&1; then
        log_with_timestamp "✅ Simple contract analysis completed"
      else
        log_with_timestamp "⚠️ Simple contract analysis failed"
      fi
      
      # Run Slither if available
      log_with_timestamp "🛡️ Running Slither security analysis..."
      if command -v slither &> /dev/null; then
        if slither "$contract_path" --solc solc > "./logs/slither/${contract_name}-report.txt" 2>&1; then
          log_with_timestamp "✅ Slither analysis completed"
        else
          log_with_timestamp "⚠️ Slither analysis completed with findings"
        fi
      else
        log_with_timestamp "ℹ️ Slither not available, skipping security analysis"
      fi
      
      # Get file stats for size
      log_with_timestamp "📏 Analyzing contract size..."
      filesize=$(stat -c%s "$contract_path")
      echo "Contract: $contract_name" > "./logs/reports/${contract_name}-size.txt"
      echo "Source size: $filesize bytes" >> "./logs/reports/${contract_name}-size.txt"
      
      # If binary was generated, get its size too
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

      # Create comprehensive test summary
      log_with_timestamp "📋 Creating test summary..."
      cat > "./logs/reports/test-summary-${contract_name}.md" <<EOF
# Test Summary for ${contract_name}

## Contract Information
- **File**: ${filename}
- **Contract Name**: ${contract_name}
- **Test Date**: $(date '+%Y-%m-%d %H:%M:%S')
- **Source Size**: ${filesize} bytes

## Analysis Results
- **Compilation**: $([ -f "/app/artifacts/${contract_name}.bin" ] && echo "✅ SUCCESSFUL" || echo "⚠️ ISSUES FOUND")
- **Foundry Tests**: $(grep -q "✅ Foundry tests passed" "$LOG_FILE" && echo "✅ PASSED" || echo "ℹ️ N/A")
- **Security Analysis**: $(grep -q "✅ Slither analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ ISSUES FOUND")
- **Contract Analysis**: $(grep -q "✅ Simple contract analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ FAILED")
EOF

      # Add binary size info if available
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
EOF

      # Add Foundry reports if they exist
      if compgen -G './test/*.t.sol' > /dev/null 2>&1; then
        cat >> "./logs/reports/test-summary-${contract_name}.md" <<EOF
- Foundry Test Report: \`logs/foundry/foundry-test-report.json\`
- Coverage Report: \`logs/coverage/foundry-lcov.info\`
EOF
      fi

      cat >> "./logs/reports/test-summary-${contract_name}.md" <<EOF
- Full Log: \`logs/evm-test.log\`

## Contract Analysis Highlights

EOF

      # Add simplified analysis highlights
      if [ -f "./logs/reports/${contract_name}-analysis.txt" ]; then
        grep "Simple Security Checks:" -A 20 "./logs/reports/${contract_name}-analysis.txt" >> "./logs/reports/test-summary-${contract_name}.md" || true
      fi

      log_with_timestamp "📋 Test summary created: logs/reports/test-summary-${contract_name}.md"
      log_with_timestamp "🏁 All EVM analysis complete for $filename"
      log_with_timestamp "=========================================="

      # Run AI-enhanced aggregation and log result
      log_with_timestamp "🤖 Starting AI-enhanced aggregation..."
      if node /app/scripts/aggregate-all-logs.js >> "$LOG_FILE" 2>&1; then
        log_with_timestamp "✅ AI-enhanced report generated: /app/logs/reports/complete-contracts-report.md"
      else
        log_with_timestamp "❌ AI-enhanced aggregation failed (see log for details)"
      fi
      log_with_timestamp "=========================================="

    } 2>&1
  fi
done
