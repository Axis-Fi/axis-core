#!/bin/bash

# Usage:
# ./uniswap_dtl_salts.sh <2 | 3> <atomic | batch>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
VERSION=$1
MODE=$2

# Check that the version is 2 or 3
if [ "$VERSION" != "2" ] && [ "$VERSION" != "3" ]
then
  echo "Invalid version specified. Provide '2' or '3' after the command as argument 1."
  exit 1
fi

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
echo "Using Uniswap version: $VERSION"
echo "Using variant: $MODE"

forge script ./script/salts/dtl/UniswapDTLSalts.s.sol:UniswapDTLSalts --sig "generate(string,string,bool)()" $CHAIN $VERSION $ATOMIC
