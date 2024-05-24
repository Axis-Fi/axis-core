#!/bin/bash

# Usage:
# ./baseline_allocated_allowlist_salts.sh <kernel> <owner> <reserve token>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
KERNEL=$1
OWNER=$2
RESERVE_TOKEN=$3

# Check that the kernel is a 40-byte address with a 0x prefix
if [[ ! "$KERNEL" =~ ^0x[0-9a-fA-F]{40}$ ]]
then
  echo "Invalid kernel address specified. Provide a 40-byte address with a 0x prefix as argument 2."
  exit 1
fi

# Check that the owner is a 40-byte address with a 0x prefix
if [[ ! "$OWNER" =~ ^0x[0-9a-fA-F]{40}$ ]]
then
  echo "Invalid owner address specified. Provide a 40-byte address with a 0x prefix as argument 3."
  exit 1
fi

# Check that the reserve token is a 40-byte address with a 0x prefix
if [[ ! "$RESERVE_TOKEN" =~ ^0x[0-9a-fA-F]{40}$ ]]
then
  echo "Invalid reserve token address specified. Provide a 40-byte address with a 0x prefix as argument 4."
  exit 1
fi

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"
echo "Using kernel: $KERNEL"
echo "Using owner: $OWNER"
echo "Using reserve token: $RESERVE_TOKEN"

forge script ./script/salts/BaselineAllocatedAllowlistSalts.s.sol:BaselineAllocatedAllowlistSalts --sig "generate(string,string,string,string)()" $CHAIN $KERNEL $OWNER $RESERVE_TOKEN
