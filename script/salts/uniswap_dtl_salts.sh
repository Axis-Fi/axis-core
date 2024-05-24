#!/bin/bash

# Usage:
# ./uniswap_dtl_salts.sh --version <2 | 3> --type <atomic | batch>
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

# Check that the version is 2 or 3
if [ "$version" != "2" ] && [ "$version" != "3" ]
then
  echo "Invalid version specified. Provide '2' or '3' after the --version flag."
  exit 1
fi

# Check that the mode is "atomic" or "batch"
if [ "$type" != "atomic" ] && [ "$type" != "batch" ]
then
  echo "Invalid mode specified. Provide 'atomic' or 'batch' after the --type flag."
  exit 1
fi

# Set flag for atomic or batch auction
ATOMIC=$( if [ "$type" == "atomic" ]; then echo "true"; else echo "false"; fi )

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"
echo "Using Uniswap version: $version"
echo "Using auction type: $type"

forge script ./script/salts/UniswapDTLSalts.s.sol:UniswapDTLSalts --sig "generate(string,string,bool)()" $CHAIN $version $ATOMIC
