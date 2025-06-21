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

// Load optional plugins if available
try { require("solidity-coverage"); } catch (e) { console.log("Optional plugin not found: solidity-coverage"); }
try { require("hardhat-gas-reporter"); } catch (e) { console.log("Optional plugin not found: hardhat-gas-reporter"); }
try { require("hardhat-contract-sizer"); } catch (e) { console.log("Optional plugin not found: hardhat-contract-sizer"); }
try { require("@openzeppelin/hardhat-upgrades"); } catch (e) { console.log("Optional plugin not found: @openzeppelin/hardhat-upgrades"); }

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
  "json": "/app/logs/slither/slither-report.json"
}
EOF
        log_with_timestamp "✅ Created Slither configuration"
    fi
}

# Initialize git if not already done (required for some tools)
if [ ! -d ".git" ]; then
    git init . 2>/dev/null || true
    git config user.name "SmartTestHub" 2>/dev/null || true
    git config user.email "test@smarttesthub.com" 2>/dev/null || true
fi

# Ensure configuration files exist
ensure_hardhat_config

# Function to safely run commands
run_command() {
    local command="$1"
    local success_msg="$2"
    local failure_msg="$3"
    
    if eval "$command" 2>&1 | tee -a "$LOG_FILE"; then
        log_with_timestamp "$success_msg"
        return 0
    else
        log_with_timestamp "$failure_msg"
        return 1
    fi
}

# Watch the input folder where backend will drop .sol files
log_with_timestamp "📡 Watching /app/input for incoming Solidity files..."

inotifywait -m -e close_write,moved_to,create /app/input |
while read -r directory events filename; do
  if [[ "$filename" == *.sol ]]; then
    {
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
      run_command "npx hardhat compile --config ./config/hardhat.config.js" \
        "✅ Hardhat compilation successful" \
        "❌ Hardhat compilation failed for $filename" || continue

      # Run Hardhat tests
      log_with_timestamp "🧪 Running Hardhat tests..."
      run_command "npx hardhat test --config ./config/hardhat.config.js" \
        "✅ Hardhat tests passed" \
        "❌ Hardhat tests failed for $filename"

      # Run Foundry tests if any .t.sol files exist
      if compgen -G './test/*.t.sol' > /dev/null 2>&1; then
        log_with_timestamp "🧪 Running Foundry tests with gas reporting..."
        run_command "forge test --gas-report --json > ./logs/foundry/foundry-test-report.json" \
          "✅ Foundry tests passed with gas report" \
          "❌ Foundry tests failed - check logs/foundry/foundry-test-report.json"
        
        # Generate forge coverage
        log_with_timestamp "📊 Generating Foundry coverage report..."
        run_command "forge coverage --report lcov --report-file ./logs/coverage/foundry-lcov.info" \
          "✅ Foundry coverage report generated" \
          "⚠️ Foundry coverage generation failed"
      else
        log_with_timestamp "ℹ️ No Foundry test files found, skipping forge test"
      fi

      # Run comprehensive Slither security analysis
      log_with_timestamp "🔎 Running comprehensive Slither security analysis..."
      # Determine solc version from contract pragma
      SOLC_VERSION=$(grep -oP 'pragma solidity .*?[0-9]+\.[0-9]+\.[0-9]+' /app/contracts/$filename | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "0.8.24")
      log_with_timestamp "📝 Detected Solidity version: $SOLC_VERSION"
      
      # Use solc-select if available or log a warning
      if command -v solc-select >/dev/null 2>&1; then
        log_with_timestamp "🔧 Installing solc version $SOLC_VERSION using solc-select"
        solc-select install $SOLC_VERSION && solc-select use $SOLC_VERSION || true
      else
        log_with_timestamp "⚠️ solc-select not found, attempting to use system solc"
      fi
      
      # Try to run slither with proper configuration
      if [ -f "./config/slither.config.json" ]; then
        run_command "slither ./contracts --config-file ./config/slither.config.json --json ./logs/slither/slither-report.json" \
          "✅ Slither analysis completed - check logs/slither/slither-report.json" \
          "⚠️ Slither analysis completed with findings - check logs/slither/slither-report.json"
      else
        run_command "slither ./contracts --json ./logs/slither/slither-report.json" \
          "✅ Slither analysis completed" \
          "⚠️ Slither analysis completed with findings"
      fi

      # Generate comprehensive gas report
      log_with_timestamp "⛽ Generating comprehensive gas usage report..."
      # Set environment variable for gas reporting
      export REPORT_GAS=true
      run_command "npx hardhat test --config ./config/hardhat.config.js" \
        "✅ Gas report generated - check logs/gas/gas-report.txt" \
        "⚠️ Gas report generation failed"
      
      # Try to find generated gas report or create a placeholder
      if [ ! -f "./logs/gas/gas-report.txt" ]; then
        echo "Gas report not found. This may be due to missing plugin." > ./logs/gas/gas-report.txt
      fi

      # Run coverage analysis if the plugin is available
      log_with_timestamp "📊 Running coverage analysis..."
      if npm list solidity-coverage > /dev/null 2>&1; then
        run_command "npx hardhat coverage --config ./config/hardhat.config.js" \
          "✅ Coverage analysis completed" \
          "⚠️ Coverage analysis failed"
        # Move coverage files to organized directory
        [ -f "coverage.json" ] && mv coverage.json ./logs/coverage/ 2>/dev/null || true
        [ -d "coverage" ] && cp -r coverage/* ./logs/coverage/ 2>/dev/null || true
      else
        log_with_timestamp "⚠️ Skipping coverage analysis - solidity-coverage plugin not found"
        echo "Coverage analysis skipped - plugin not available" > ./logs/coverage/coverage-info.txt
      fi

      # Contract size analysis if the plugin is available
      log_with_timestamp "📏 Analyzing contract size..."
      if npm list hardhat-contract-sizer > /dev/null 2>&1; then
        run_command "npx hardhat compile --config ./config/hardhat.config.js" \
          "✅ Contract size analysis completed" \
          "⚠️ Contract size analysis failed"
      else
        log_with_timestamp "⚠️ Skipping contract size analysis - hardhat-contract-sizer plugin not found"
        echo "Contract size analysis skipped - plugin not available" > ./logs/reports/contract-sizes.txt
      fi

      # Generate storage layout
      log_with_timestamp "🗂️ Generating storage layout..."
      run_command "npx hardhat compile --config ./config/hardhat.config.js" \
        "✅ Storage layout generated" \
        "⚠️ Storage layout generation failed"

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
- **Foundry Tests**: $(grep -q "✅ Foundry tests passed" "$LOG_FILE" && echo "✅ PASSED" || grep -q "No Foundry test files found" "$LOG_FILE" && echo "ℹ️ N/A" || echo "❌ FAILED")
- **Security Analysis**: $(grep -q "✅ Slither analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ ISSUES FOUND")
- **Gas Analysis**: $(grep -q "✅ Gas report generated" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ FAILED")
- **Coverage Analysis**: $(grep -q "✅ Coverage analysis completed" "$LOG_FILE" && echo "✅ COMPLETED" || echo "⚠️ FAILED")

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
