#!/bin/bash

# Usage:
# ./allowlist_salts.sh <atomic | batch>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
MODE=$1

# Check that the mode is "atomic" or "batch"
if [ "$MODE" != "atomic" ] && [ "$MODE" != "batch" ]
then
  echo "Invalid mode specified. Provide 'atomic' or 'batch' after the command as argument 2."
  exit 1
fi

# Set flag for atomic or batch auction
ATOMIC=$( if [ "$MODE" == "atomic" ]; then echo "true"; else echo "false"; fi )

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"
echo "Using variant: $MODE"

forge script ./script/salts/allowlist/AllowListSalts.s.sol:AllowlistSalts --sig "generate(string,bool)()" $CHAIN $ATOMIC
