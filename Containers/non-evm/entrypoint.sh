#!/bin/bash
set -e

# Simple environment setup for Rust/Solana
export CARGO_TARGET_DIR=/app/target
export RUST_BACKTRACE=0

echo "🚀 Starting Simplified Solana Container..."
echo "📂 Watching for Rust contract files..."

# Create necessary directories
mkdir -p /app/input
mkdir -p /app/logs
mkdir -p /app/contracts
mkdir -p /app/src

LOG_FILE="/app/logs/test.log"
: > "$LOG_FILE"

# Simple logging function
log_with_timestamp() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $message" | tee -a "$LOG_FILE"
}

# Create basic Cargo.toml for contract
create_cargo_config() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "📝 Creating Cargo configuration for $contract_name..."
    
    cat > "$contract_subdir/Cargo.toml" <<EOF
[package]
name = "$contract_name"
version = "0.1.0"
edition = "2021"

[dependencies]
solana-program = "1.18.26"
borsh = "0.10.4"
borsh-derive = "0.10.4"
thiserror = "1.0"

[dev-dependencies]
solana-program-test = "1.18.26"
tokio = { version = "1.0", features = ["full"] }

[lib]
name = "$contract_name"
path = "src/lib.rs"
crate-type = ["cdylib", "lib"]

[features]
default = []
no-entrypoint = []
EOF
    log_with_timestamp "✅ Created Cargo config for $contract_name"
}

# Generate basic test file
generate_basic_tests() {
    local contract_name="$1"
    local contract_subdir="$2"
    
    log_with_timestamp "🧪 Generating basic test suite for $contract_name..."
    
    mkdir -p "$contract_subdir/tests"
    
    cat > "$contract_subdir/tests/integration.rs" <<EOF
use solana_program_test::*;
use solana_sdk::{
    account::Account,
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    rent::Rent,
    signature::Signer,
    transaction::Transaction,
};

#[tokio::test]
async fn test_basic_functionality() {
    let program_id = Pubkey::new_unique();
    let (mut banks_client, payer, recent_blockhash) = ProgramTest::new(
        "$contract_name",
        program_id,
        processor!(${contract_name}::process_instruction),
    )
    .start()
    .await;

    // Basic test to ensure program loads
    let account = banks_client
        .get_account(program_id)
        .await
        .expect("get_account")
        .expect("account exists");
    
    assert!(account.executable);
}
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
        echo "=== Basic Rust/Solana Security Analysis ==="
        echo "Contract: $contract_name"
        echo "Date: $(date)"
        echo ""
        
        # Basic pattern checks for Solana programs
        if grep -n "unsafe" "$contract_path"; then
            echo "WARNING: Unsafe code found - review carefully"
        else
            echo "✅ No unsafe code blocks found"
        fi
        
        if grep -n "unwrap()" "$contract_path"; then
            echo "WARNING: unwrap() calls found - consider proper error handling"
        else
            echo "✅ No unwrap() calls found"
        fi
        
        if grep -n "AccountInfo" "$contract_path"; then
            echo "✅ AccountInfo usage found - standard Solana pattern"
        fi
        
        echo "=== Analysis Complete ==="
    } > "$security_log"
    
    log_with_timestamp "✅ Basic security analysis completed"
}

log_with_timestamp "📡 Watching for Rust contract files in /app/input..."

# Main file monitoring loop
if command -v inotifywait &> /dev/null; then
    inotifywait -m -e close_write,moved_to /app/input --format '%w%f' |
    while read FILE_PATH; do
        if [[ "$FILE_PATH" == *.rs ]]; then
            filename=$(basename "$FILE_PATH")
            contract_name=$(basename "$filename" .rs)
            
            # Simple lock mechanism
            lock_file="/tmp/processing_${contract_name}.lock"
            if [ -f "$lock_file" ]; then
                continue
            fi
            echo "$$" > "$lock_file"
            
            {
                start_time=$(date +%s)
                log_with_timestamp "🆕 Processing Rust contract: $filename"
                
                contract_subdir="/app/contracts/${contract_name}"
                mkdir -p "$contract_subdir/src"
                mkdir -p "$contract_subdir/logs"
                cp "$FILE_PATH" "$contract_subdir/src/lib.rs"
                
                # Create configuration and tests
                create_cargo_config "$contract_name" "$contract_subdir"
                generate_basic_tests "$contract_name" "$contract_subdir"
                
                # Build contract
                log_with_timestamp "🔨 Building $contract_name..."
                if (cd "$contract_subdir" && cargo build > "$contract_subdir/logs/build.log" 2>&1); then
                    log_with_timestamp "✅ Build successful"
                    
                    # Run basic analysis
                    run_basic_security_analysis "$contract_name" "$contract_subdir/src/lib.rs" "$contract_subdir"
                    
                    # Run tests
                    (cd "$contract_subdir" && cargo test > "$contract_subdir/logs/test.log" 2>&1) || {
                        log_with_timestamp "⚠️ Some tests may have failed - check logs"
                    }
                    
                else
                    log_with_timestamp "❌ Build failed for $contract_name"
                    if [ -f "$contract_subdir/logs/build.log" ]; then
                        cat "$contract_subdir/logs/build.log" | tail -10 | while IFS= read -r line; do
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
        for FILE_PATH in /app/input/*.rs; do
            [ -e "$FILE_PATH" ] || continue
            # Similar processing logic would go here
        done
        sleep 5
    done
fi