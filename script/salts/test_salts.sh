#!/bin/bash

# Usage:
# ./test_salts.sh

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"

# Generate bytecode
forge script ./script/salts/TestSalts.s.sol:TestSalts --sig "generate(string)()" $CHAIN
