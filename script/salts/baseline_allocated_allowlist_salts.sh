#!/bin/bash

# Usage:
# ./baseline_allocated_allowlist_salts.sh --kernel <kernel> --owner <owner> --reserveToken <reserve token>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        v="${1/--/}"
        declare $v="$2"
   fi

  shift
done

# Check that the CHAIN environment variable is set
if [ -z "$CHAIN" ]
then
  echo "CHAIN environment variable is not set. Please set it in the .env file or provide it as an environment variable."
  exit 1
fi

# Check that the kernel is a 40-byte address with a 0x prefix
if [[ ! "$kernel" =~ ^0x[0-9a-fA-F]{40}$ ]]
then
  echo "Invalid kernel address specified. Provide a 40-byte address with a 0x prefix after the --kernel flag."
  exit 1
fi

# Check that the owner is a 40-byte address with a 0x prefix
if [[ ! "$owner" =~ ^0x[0-9a-fA-F]{40}$ ]]
then
  echo "Invalid owner address specified. Provide a 40-byte address with a 0x prefix after the --owner flag."
  exit 1
fi

# Check that the reserve token is a 40-byte address with a 0x prefix
if [[ ! "$reserveToken" =~ ^0x[0-9a-fA-F]{40}$ ]]
then
  echo "Invalid reserve token address specified. Provide a 40-byte address with a 0x prefix after the --reserveToken flag."
  exit 1
fi

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"
echo "Using kernel: $kernel"
echo "Using owner: $owner"
echo "Using reserve token: $reserveToken"

forge script ./script/salts/BaselineAllocatedAllowlistSalts.s.sol:BaselineAllocatedAllowlistSalts --sig "generate(string,string,string,string)()" $CHAIN $kernel $owner $reserveToken
