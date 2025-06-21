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

LOG_FILE="/app/logs/evm-test.log"

# Clear old log (or comment this line if you prefer appending)
: > "$LOG_FILE"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to ensure Hardhat config exists
ensure_hardhat_config() {
    if [ ! -f "/app/config/hardhat.config.js" ]; then
        log_with_timestamp "📝 Creating Hardhat configuration..."
        cat > "/app/config/hardhat.config.js" <<EOF
require("@nomicfoundation/hardhat-toolbox");
require("solidity-coverage");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");
require("hardhat-docgen");
require("hardhat-storage-layout");
require("@openzeppelin/hardhat-upgrades");

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
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    outputFile: "./logs/gas/gas-report.txt",
    noColors: true,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
    outputFile: "./logs/reports/contract-sizes.txt",
  },
  docgen: {
    path: './logs/docs',
    clear: true,
    runOnCompile: true,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
EOF
        log_with_timestamp "✅ Created enhanced Hardhat configuration"
    fi
    
    # Ensure Slither config exists
    if [ ! -f "/app/config/slither.config.json" ]; then
        log_with_timestamp "📝 Creating Slither configuration..."
        cat > "/app/config/slither.config.json" <<EOF
{
  "detectors_to_exclude": [],
  "exclude_informational": false,
  "exclude_low": false,
  "exclude_medium": false,
  "exclude_high": false,
  "solc_disable_warnings": false,
  "json": "/app/logs/slither/slither-report.json",
  "solc_remaps": [
    "@openzeppelin/=node_modules/@openzeppelin/",
    "@chainlink/=node_modules/@chainlink/"
  ],
  "filter_paths": "node_modules",
  "solc": "hardhat"
}
EOF
        log_with_timestamp "✅ Created Slither configuration"
    fi

    # Check for missing npm packages and install them
    log_with_timestamp "🔍 Checking for required npm packages..."
    cd /app
    
    # Check for hardhat-contract-sizer package
    if ! npm list hardhat-contract-sizer 2>/dev/null | grep -q "hardhat-contract-sizer"; then
        log_with_timestamp "📦 Installing hardhat-contract-sizer..."
        npm install --save-dev hardhat-contract-sizer
    fi
    
    # Check for hardhat-gas-reporter package
    if ! npm list hardhat-gas-reporter 2>/dev/null | grep -q "hardhat-gas-reporter"; then
        log_with_timestamp "📦 Installing hardhat-gas-reporter..."
        npm install --save-dev hardhat-gas-reporter
    fi
    
    # Check for solidity-coverage package
    if ! npm list solidity-coverage 2>/dev/null | grep -q "solidity-coverage"; then
        log_with_timestamp "📦 Installing solidity-coverage..."
        npm install --save-dev solidity-coverage
    fi
    
    # Install solc locally for Slither
    if ! command -v solc-select &> /dev/null; then
        log_with_timestamp "📦 Installing solc-select for Slither..."
        pip install solc-select
        solc-select install 0.8.18
        solc-select use 0.8.18
    fi

    log_with_timestamp "✅ Package checks completed"
}

# Initialize git if not already done (required for some tools)
if [ ! -d ".git" ]; then
    git init . 2>/dev/null || true
    git config user.name "SmartTestHub" 2>/dev/null || true
    git config user.email "test@smarttesthub.com" 2>/dev/null || true
fi

# Ensure configuration files exist
ensure_hardhat_config

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
        # Only process if last processed more than 5 seconds ago
        if (( $CURRENT_TIME - $LAST_PROCESSED < 5 )); then
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
      
      # Create a basic test file if none exists
      if [ ! -f "/app/test/${contract_name}.test.js" ]; then
        cat > "/app/test/${contract_name}.test.js" <<EOF
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("${contract_name}", function () {
  let contract;
  
  beforeEach(async function () {
    const Contract = await ethers.getContractFactory("${contract_name}");
    contract = await Contract.deploy();
    await contract.deployed();
  });

  it("Should deploy successfully", async function () {
    expect(contract.address).to.not.be.undefined;
    expect(contract.address).to.match(/^0x[a-fA-F0-9]{40}$/);
  });

  it("Should have correct initial state", async function () {
    // Add contract-specific tests here
    expect(contract.address).to.be.properAddress;
  });
});
EOF
        log_with_timestamp "📝 Created enhanced test file for $contract_name"
      fi

      # Run Hardhat compilation
      log_with_timestamp "🔨 Compiling contract with Hardhat..."
      if npx hardhat compile --config ./config/hardhat.config.js 2>&1 | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ Hardhat compilation successful"
      else
        log_with_timestamp "❌ Hardhat compilation failed for $filename"
        continue
      fi

      # Run Hardhat tests
      log_with_timestamp "🧪 Running Hardhat tests..."
      if HARDHAT_NETWORK=hardhat npx hardhat test --config ./config/hardhat.config.js 2>&1 | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ Hardhat tests passed"
      else
        log_with_timestamp "❌ Hardhat tests failed for $filename"
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

      # Run comprehensive Slither security analysis
      log_with_timestamp "🔎 Running comprehensive Slither security analysis..."
      if [ -f "./config/slither.config.json" ]; then
        # Use --solc to directly specify the solc version
        if slither ./contracts --solc solc --config-file ./config/slither.config.json 2>&1 | tee -a "$LOG_FILE"; then
          log_with_timestamp "✅ Slither analysis completed - check logs/slither/slither-report.json"
        else
          log_with_timestamp "⚠️ Slither analysis completed with findings - check logs/slither/slither-report.json"
        fi
      else
        if slither ./contracts --solc solc 2>&1 | tee -a "$LOG_FILE"; then
          log_with_timestamp "✅ Slither analysis completed"
        else
          log_with_timestamp "⚠️ Slither analysis completed with findings"
        fi
      fi

      # Generate comprehensive gas report
      log_with_timestamp "⛽ Generating comprehensive gas usage report..."
      if HARDHAT_NETWORK=hardhat npx hardhat test --config ./config/hardhat.config.js 2>&1 | tee ./logs/gas/gas-report.txt; then
        log_with_timestamp "✅ Gas report generated - check logs/gas/gas-report.txt"
      else
        log_with_timestamp "⚠️ Gas report generation failed"
      fi

      # Run coverage analysis
      log_with_timestamp "📊 Running coverage analysis..."
      if HARDHAT_NETWORK=hardhat npx hardhat coverage --config ./config/hardhat.config.js 2>&1 | tee -a "$LOG_FILE"; then
        log_with_timestamp "✅ Coverage analysis completed"
        # Move coverage files to organized directory
        [ -f "coverage.json" ] && mv coverage.json ./logs/coverage/ 2>/dev/null || true
        [ -d "coverage" ] && cp -r coverage/* ./logs/coverage/ 2>/dev/null || true
      else
        log_with_timestamp "⚠️ Coverage analysis failed"
      fi

      # Contract size analysis
      log_with_timestamp "📏 Analyzing contract size..."
      if npx hardhat run --network hardhat ./scripts/check-contract-size.js 2>&1 | tee ./logs/reports/contract-sizes.txt; then
        log_with_timestamp "✅ Contract size analysis completed"
      else
        # Try direct method if script fails
        log_with_timestamp "⚠️ Contract size script failed, trying direct method..."
        # Create a temporary script
        cat > ./scripts/check-contract-size.js <<EOF
async function main() {
  const contractName = "${contract_name}";
  try {
    const artifact = await hre.artifacts.readArtifact(contractName);
    const size = (artifact.deployedBytecode.length - 2) / 2;
    console.log(\`Contract: \${contractName}\`);
    console.log(\`Size: \${size} bytes\`);
    console.log(\`Size limit: 24576 bytes\`);
    console.log(\`Status: \${size <= 24576 ? 'Within limit ✅' : 'Exceeds limit ❌'}\`);
  } catch (e) {
    console.error("Error checking contract size:", e.message);
  }
}
main().catch(console.error);
EOF
        mkdir -p ./scripts
        
        if npx hardhat run --network hardhat ./scripts/check-contract-size.js 2>&1 | tee ./logs/reports/contract-sizes.txt; then
          log_with_timestamp "✅ Contract size analysis completed"
        else
          log_with_timestamp "❌ Contract size analysis failed"
        fi
      fi

      # Generate storage layout
      log_with_timestamp "🗂️ Generating storage layout..."
      if HARDHAT_NETWORK=hardhat npx hardhat check --config ./config/hardhat.config.js 2>&1 | tee ./logs/reports/storage-layout.txt; then
        log_with_timestamp "✅ Storage layout generated"
      else
        log_with_timestamp "⚠️ Storage layout generation failed"
      fi

      # Create comprehensive test summary
      log_with_timestamp "📋 Creating test summary..."
      cat > "./logs/reports/test-summary-${contract_name}.md" <<EOF
# Test Summary for ${contract_name}

## Contract Information
- **File**: ${filename}
- **Contract Name**: ${contract_name}
- **Test Date**: $(date '+%Y-%m-%d %H:%M:%S')

## Test Results
- **Hardhat Compilation**: $(grep -q "✅ Hardhat compilation successful" "$LOG_FILE" && echo "✅ PASSED" || echo "❌ FAILED")
- **Hardhat Tests**: $(grep -q "✅ Hardhat tests passed" "$LOG_FILE" && echo "✅ PASSED" || echo "❌ FAILED")
- **Foundry Tests**: $(grep -q "✅ Foundry tests passed" "$LOG_FILE" && echo "✅ PASSED" || echo "ℹ️ N/A")
- **Security Analysis**: $(grep -q "✅ Slither analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ ISSUES FOUND")
- **Gas Analysis**: $(grep -q "✅ Gas report generated" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ FAILED")
- **Coverage Analysis**: $(grep -q "✅ Coverage analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ FAILED")
- **Contract Size**: $(grep -q "Within limit ✅" "./logs/reports/contract-sizes.txt" 2>/dev/null && echo "✅ WITHIN LIMIT" || echo "⚠️ CHECK REQUIRED")

## Files Generated
- Security Report: \`logs/slither/slither-report.json\`
- Gas Report: \`logs/gas/gas-report.txt\`
- Coverage Report: \`logs/coverage/\`
- Contract Sizes: \`logs/reports/contract-sizes.txt\`
- Full Log: \`logs/evm-test.log\`

EOF
      log_with_timestamp "📋 Test summary created: logs/reports/test-summary-${contract_name}.md"

      log_with_timestamp "🏁 All EVM analysis complete for $filename"
      log_with_timestamp "==========================================\n"
      
    } 2>&1
  fi
done
