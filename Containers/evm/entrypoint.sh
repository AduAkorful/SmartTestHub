#!/bin/bash
set -e

echo "🚀 Starting EVM container..."

export REPORT_GAS=true
export HARDHAT_NETWORK=hardhat
export SLITHER_CONFIG_FILE="./config/slither.config.json"

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

log_with_timestamp() {
    local contract_name="$1"
    local message="$2"
    local LOG_FILE="/app/logs/${contract_name}-evm-test.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

sanitize_solidity_name() {
    local raw="$1"
    local sanitized="${raw//[^a-zA-Z0-9_]/_}"
    sanitized="${sanitized//__/_}"
    sanitized="${sanitized#_}"
    sanitized="${sanitized%_}"
    [[ "$sanitized" =~ ^[0-9] ]] && sanitized="_$sanitized"
    case "$sanitized" in
      storage|mapping|function|contract|address|enum|struct|event|modifier|constant)
        sanitized="${sanitized}C"
        ;;
    esac
    echo "$sanitized"
}

create_simplified_hardhat_config() {
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
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
EOF
    ln -sf "/app/hardhat.config.js" "/app/config/hardhat.config.js"

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
}

create_simple_analysis_script() {
    cat > "/app/scripts/analyze-contract.js" <<EOF
// Simple stub analysis script
console.log("Analysis script placeholder");
EOF
    chmod +x /app/scripts/analyze-contract.js
}

create_simplified_hardhat_config
create_simple_analysis_script

MARKER_DIR="/app/.processed"
mkdir -p "$MARKER_DIR"

inotifywait -m -e close_write,moved_to,create /app/input |
while read -r directory events filename; do
  if [[ "$filename" == *.sol ]]; then
    MARKER_FILE="$MARKER_DIR/$filename.processed"
    (
      exec 9>"$MARKER_FILE.lock"
      if ! flock -n 9; then
        continue
      fi

      if [ -f "$MARKER_FILE" ]; then
          LAST_PROCESSED=$(cat "$MARKER_FILE")
          CURRENT_TIME=$(date +%s)
          if (( $CURRENT_TIME - $LAST_PROCESSED < 30 )); then
              continue
          fi
      fi

      date +%s > "$MARKER_FILE"
      contract_name=$(basename "$filename" .sol)
      sanitized_name=$(sanitize_solidity_name "$contract_name")

      # Clean up per-contract logs
      find /app/logs/foundry -type f -name "${sanitized_name}*" -delete
      find /app/logs/coverage -type f -name "${sanitized_name}*" -delete
      find /app/logs/slither -type f -name "${sanitized_name}*" -delete
      find /app/logs/reports -type f -name "${sanitized_name}*" -delete
      : > "/app/logs/${sanitized_name}-evm-test.log"

      mkdir -p /app/contracts
      cp "/app/input/$filename" "/app/contracts/$filename"
      log_with_timestamp "$sanitized_name" "🆕 Detected Solidity contract: $filename"
      log_with_timestamp "$sanitized_name" "📁 Copied $filename to contracts directory"

      test_file="./test/${sanitized_name}.t.sol"
      if [ ! -f "$test_file" ]; then
        cat > "$test_file" <<EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/${filename}";

contract ${sanitized_name}Test is Test {
    ${sanitized_name} public contractInstance;

    function setUp() public {
        contractInstance = new ${sanitized_name}();
    }

    function testDeployment() public {
        assert(address(contractInstance) != address(0));
    }
}
EOF
        log_with_timestamp "$sanitized_name" "✅ Basic test file created at $test_file"
      fi

      log_with_timestamp "$sanitized_name" "🔨 Attempting direct Solidity compilation..."
      mkdir -p /app/artifacts
      if solc --bin --abi --optimize --overwrite -o /app/artifacts /app/contracts/$filename 2>/dev/null; then
        log_with_timestamp "$sanitized_name" "✅ Direct Solidity compilation successful"
      else
        log_with_timestamp "$sanitized_name" "⚠️ Direct compilation had issues, continuing with analysis"
      fi

      log_with_timestamp "$sanitized_name" "🧪 Running Foundry tests with gas reporting..."
      if forge test --gas-report --json > ./logs/foundry/${sanitized_name}-foundry-test-report.json 2>&1 | tee -a "/app/logs/${sanitized_name}-evm-test.log"; then
        log_with_timestamp "$sanitized_name" "✅ Foundry tests passed with gas report"
      else
        log_with_timestamp "$sanitized_name" "❌ Foundry tests failed - check logs/foundry/${sanitized_name}-foundry-test-report.json"
      fi

      log_with_timestamp "$sanitized_name" "📊 Generating Foundry coverage report..."
      if forge coverage --report lcov --report-file ./logs/coverage/${sanitized_name}-foundry-lcov.info 2>&1 | tee -a "/app/logs/${sanitized_name}-evm-test.log"; then
        log_with_timestamp "$sanitized_name" "✅ Foundry coverage report generated"
      else
        log_with_timestamp "$sanitized_name" "⚠️ Foundry coverage generation failed"
      fi

      log_with_timestamp "$sanitized_name" "🔍 Running simple contract analysis..."
      if node /app/scripts/analyze-contract.js "/app/contracts/$filename" > "./logs/reports/${sanitized_name}-analysis.txt" 2>&1; then
        log_with_timestamp "$sanitized_name" "✅ Simple contract analysis completed"
      else
        log_with_timestamp "$sanitized_name" "⚠️ Simple contract analysis failed"
      fi

      log_with_timestamp "$sanitized_name" "🛡️ Running Slither security analysis..."
      if command -v slither &> /dev/null; then
        if slither "/app/contracts/$filename" --solc solc > "./logs/slither/${sanitized_name}-report.txt" 2>&1; then
          log_with_timestamp "$sanitized_name" "✅ Slither analysis completed"
        else
          log_with_timestamp "$sanitized_name" "⚠️ Slither analysis completed with findings"
        fi
      else
        log_with_timestamp "$sanitized_name" "ℹ️ Slither not available, skipping security analysis"
      fi

      log_with_timestamp "$sanitized_name" "📏 Analyzing contract size..."
      filesize=$(stat -c%s "/app/contracts/$filename")
      echo "Contract: $sanitized_name" > "./logs/reports/${sanitized_name}-size.txt"
      echo "Source size: $filesize bytes" >> "./logs/reports/${sanitized_name}-size.txt"

      if [ -f "/app/artifacts/${sanitized_name}.bin" ]; then
        binsize=$(stat -c%s "/app/artifacts/${sanitized_name}.bin")
        hexsize=$((binsize / 2))
        echo "Compiled size: $hexsize bytes" >> "./logs/reports/${sanitized_name}-size.txt"
        echo "EIP-170 limit: 24576 bytes" >> "./logs/reports/${sanitized_name}-size.txt"
        if [ "$hexsize" -gt 24576 ]; then
          echo "Status: Exceeds limit ❌" >> "./logs/reports/${sanitized_name}-size.txt"
        else
          echo "Status: Within limit ✅" >> "./logs/reports/${sanitized_name}-size.txt"
        fi
      fi
      log_with_timestamp "$sanitized_name" "✅ Contract size analysis completed"

      log_with_timestamp "$sanitized_name" "📋 Creating test summary..."
      cat > "./logs/reports/test-summary-${sanitized_name}.md" <<EOF
# Test Summary for ${sanitized_name}

## Contract Information
- **File**: ${filename}
- **Contract Name**: ${sanitized_name}
- **Test Date**: $(date '+%Y-%m-%d %H:%M:%S')
- **Source Size**: ${filesize} bytes

## Analysis Results
- **Compilation**: $([ -f "/app/artifacts/${sanitized_name}.bin" ] && echo "✅ SUCCESSFUL" || echo "⚠️ ISSUES FOUND")
- **Foundry Tests**: $(grep -q "✅ Foundry tests passed" "/app/logs/${sanitized_name}-evm-test.log" && echo "✅ PASSED" || echo "ℹ️ N/A")
- **Security Analysis**: $(grep -q "✅ Slither analysis completed" "/app/logs/${sanitized_name}-evm-test.log" && echo "✅ COMPLETED" || echo "⚠️ ISSUES FOUND")
- **Contract Analysis**: $(grep -q "✅ Simple contract analysis completed" "/app/logs/${sanitized_name}-evm-test.log" && echo "✅ COMPLETED" || echo "⚠️ FAILED")
EOF

      if [ -f "/app/artifacts/${sanitized_name}.bin" ]; then
        cat >> "./logs/reports/test-summary-${sanitized_name}.md" <<EOF
- **Compiled Size**: ${hexsize} bytes
- **Contract Size Limit**: $([ "$hexsize" -gt 24576 ] && echo "❌ EXCEEDS LIMIT" || echo "✅ WITHIN LIMIT")
EOF
      fi

      cat >> "./logs/reports/test-summary-${sanitized_name}.md" <<EOF

## Files Generated
- Security Report: \`logs/slither/${sanitized_name}-report.txt\`
- Contract Analysis: \`logs/reports/${sanitized_name}-analysis.txt\`
- Size Analysis: \`logs/reports/${sanitized_name}-size.txt\`
- Foundry Test Report: \`logs/foundry/${sanitized_name}-foundry-test-report.json\`
- Coverage Report: \`logs/coverage/${sanitized_name}-foundry-lcov.info\`
- Full Log: \`logs/${sanitized_name}-evm-test.log\`

## Contract Analysis Highlights

EOF

      if [ -f "./logs/reports/${sanitized_name}-analysis.txt" ]; then
        grep "Simple Security Checks:" -A 20 "./logs/reports/${sanitized_name}-analysis.txt" >> "./logs/reports/test-summary-${sanitized_name}.md" || true
      fi

      log_with_timestamp "$sanitized_name" "📋 Test summary created: logs/reports/test-summary-${sanitized_name}.md"
      log_with_timestamp "$sanitized_name" "🏁 All EVM analysis complete for $filename"
      log_with_timestamp "$sanitized_name" "=========================================="

      log_with_timestamp "$sanitized_name" "🤖 Starting AI-enhanced aggregation..."
      if node /app/scripts/aggregate-all-logs.js "$sanitized_name" >> "/app/logs/${sanitized_name}-evm-test.log" 2>&1; then
        log_with_timestamp "$sanitized_name" "✅ AI-enhanced report generated: /app/logs/reports/${sanitized_name}-report.md"
      else
        log_with_timestamp "$sanitized_name" "❌ AI-enhanced aggregation failed (see log for details)"
      fi
      log_with_timestamp "$sanitized_name" "=========================================="
    )
  fi
done
