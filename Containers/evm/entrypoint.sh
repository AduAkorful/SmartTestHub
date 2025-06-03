#!/bin/bash
set -e

echo "Starting EVM tools with config..."

# Watch the test folder for changes using chokidar
# Whenever a .sol or .js test file is added/changed, rerun tests

chokidar "./test/**/*" "./contracts/**/*" "./config/**/*" -c "
  echo '🔄 Detected change, running tests...'

  # Run Hardhat tests
  echo '🧪 Running Hardhat tests...'
  npx hardhat test --config ./config/hardhat.config.js || echo '❌ Hardhat tests failed'

  # Run Foundry tests (if test folder has .t.sol files)
  if compgen -G './test/*.t.sol' > /dev/null; then
    echo '🧪 Running Foundry tests...'
    forge test || echo '❌ Foundry tests failed'
  fi

  # Run Slither analysis
  echo '🔎 Running Slither analysis...'
  slither . || echo '❌ Slither analysis failed'

  echo '✅ All EVM tests completed.'
" --initial

exec "$@"
