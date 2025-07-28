#!/bin/bash
set -e

# Simple environment setup
export NPM_CONFIG_PROGRESS=false
export REPORT_GAS=true
export HARDHAT_NETWORK=hardhat
export SLITHER_CONFIG_FILE="./config/slither.config.json"

echo "🚀 Starting Simplified EVM Container..."
echo "📂 Watching for Solidity contract files..."

# Create necessary directories
mkdir -p /app/input
mkdir -p /app/logs
mkdir -p /app/contracts
mkdir -p /app/test
mkdir -p /app/logs/reports
mkdir -p /app/config
mkdir -p /app/scripts

LOG_FILE="/app/logs/evm-test.log"
: > "$LOG_FILE"

# Simple logging function
log_with_timestamp() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $message" | tee -a "$LOG_FILE"
}

# Detect contract name from Solidity file
detect_contract_name() {
    local sol_file="$1"
    grep -E '^(contract|abstract contract|interface|library)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$sol_file" | \
    head -1 | \
    sed -E 's/^(contract|abstract contract|interface|library)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/'
}

# Create simple Hardhat configuration
create_hardhat_config() {
    local contract_name="$1"
    local contract_path="$2"
    
    if [ -f "$contract_path" ]; then
        detected_name=$(detect_contract_name "$contract_path")
        if [ -z "$detected_name" ]; then
            detected_name="$contract_name"
        fi
    else
        detected_name="$contract_name"
    fi
    
    log_with_timestamp "📝 Creating Hardhat configuration for $contract_name..."
    
    cat > "/app/hardhat.config.js" <<EOF
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: { 
      chainId: 1337,
      allowUnlimitedContractSize: true 
    },
  },
  paths: {
    sources: "./contracts/${contract_name}",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
EOF
    log_with_timestamp "✅ Created Hardhat config for $contract_name"
}

# Generate basic test file
generate_basic_tests() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "🧪 Generating basic test suite for $contract_name..."
    
    mkdir -p "$contract_subdir/test"
    
    cat > "$contract_subdir/test/${contract_name}.test.js" <<EOF
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("${contract_name} Contract Tests", function () {
    let ${contract_name,,};
    let owner, addr1, addr2;
    
    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        const ${contract_name}Factory = await ethers.getContractFactory("${contract_name}");
        
        // Try to deploy with constructor parameters if needed
        try {
            ${contract_name,,} = await ${contract_name}Factory.deploy();
        } catch (error) {
            // If deployment fails, it might need constructor parameters
            console.log("Deployment failed, contract might need constructor parameters");
            throw error;
        }
    });
    
    it("Should deploy successfully", async function () {
        expect(${contract_name,,}.target).to.be.properAddress;
    });
    
    it("Should have correct deployment parameters", async function () {
        // Add specific tests based on your contract
        expect(${contract_name,,}.target).to.not.equal(ethers.ZeroAddress);
    });
});
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
        echo "=== Basic Security Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Basic pattern checks
        echo "=== Common Security Patterns ==="
        if grep -n -E "(\.call\(|\.delegatecall\(|\.send\()" "$contract_path"; then
            echo "WARNING: External calls found - review for reentrancy protection"
        else
            echo "✅ No obvious external calls found"
        fi
        
        if grep -n -E "(onlyOwner|require.*msg\.sender)" "$contract_path"; then
            echo "✅ Access control mechanisms found"
        else
            echo "INFO: No access control mechanisms detected"
        fi
        
        if grep -n -E "(block\.timestamp|block\.number)" "$contract_path"; then
            echo "INFO: Block properties used - consider miner manipulation risks"
        fi
        
        echo "=== Analysis Complete ==="
    } > "$security_log"
    
    log_with_timestamp "✅ Basic security analysis completed"
}

# Create default configuration
create_hardhat_config "default"

log_with_timestamp "📡 Watching for Solidity contract files in /app/input..."

# Main file monitoring loop
if command -v inotifywait &> /dev/null; then
    inotifywait -m -e close_write,moved_to /app/input --format '%w%f' |
    while read FILE_PATH; do
        if [[ "$FILE_PATH" == *.sol ]]; then
            filename=$(basename "$FILE_PATH")
            contract_name=$(basename "$filename" .sol)
            
            # Simple lock mechanism
            lock_file="/tmp/processing_${contract_name}.lock"
            if [ -f "$lock_file" ]; then
                continue
            fi
            echo "$$" > "$lock_file"
            
            {
                start_time=$(date +%s)
                log_with_timestamp "🆕 Processing Solidity contract: $filename"
                
                contract_subdir="/app/contracts/${contract_name}"
                mkdir -p "$contract_subdir/logs"
                cp "$FILE_PATH" "$contract_subdir/${filename}"
                
                # Create configuration and tests
                create_hardhat_config "$contract_name" "$contract_subdir/${filename}"
                generate_basic_tests "$contract_name" "$contract_subdir"
                
                # Compile contract
                log_with_timestamp "🔨 Compiling $contract_name..."
                if (cd "$contract_subdir" && npx hardhat compile > "$contract_subdir/logs/compile.log" 2>&1); then
                    log_with_timestamp "✅ Compilation successful"
                    
                    # Run basic analysis
                    run_basic_security_analysis "$contract_name" "$contract_subdir/${filename}" "$contract_subdir"
                    
                    # Run tests
                    (cd "$contract_subdir" && npx hardhat test > "$contract_subdir/logs/test.log" 2>&1) || {
                        log_with_timestamp "⚠️ Some tests may have failed - check logs"
                    }
                    
                else
                    log_with_timestamp "❌ Compilation failed for $contract_name"
                    if [ -f "$contract_subdir/logs/compile.log" ]; then
                        cat "$contract_subdir/logs/compile.log" | tail -10 | while IFS= read -r line; do
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
        for FILE_PATH in /app/input/*.sol; do
            [ -e "$FILE_PATH" ] || continue
            # Similar processing logic as above but in polling mode
            # ... (shortened for brevity)
        done
        sleep 5
    done
fi
