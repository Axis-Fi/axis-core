#!/bin/bash

# Usage:
# ./createAuction.sh --quoteToken <address> --baseToken <address> --callback <address> --envFile <.env>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
    declare $v="$2"
  fi

  shift
done

# Get the name of the .env file or use the default
ENV_FILE=${envFile:-".env"}
echo "Sourcing environment variables from $ENV_FILE"

# Load environment file
set -a  # Automatically export all variables
source $ENV_FILE
set +a  # Disable automatic export

# Apply defaults to command-line arguments
BROADCAST=${broadcast:-false}

# Check that the CHAIN is defined
if [ -z "$CHAIN" ]
then
  echo "No chain specified. Set the CHAIN environment variable."
  exit 1
fi

# Check that the quote token is defined and is an address
if [[ ! "$quoteToken" =~ ^0x[0-9a-fA-F]{40}$ ]]
then
  echo "Invalid quote token specified. Provide the address after the --quoteToken flag."
  exit 1
fi

# Check that the base token is defined and is an address
if [[ ! "$baseToken" =~ ^0x[a-fA-F0-9]{40}$ ]]
then
  echo "Invalid base token specified. Provide the address after the --baseToken flag."
  exit 1
fi

# Check that the callback is defined and is an address
if [[ ! "$callback" =~ ^0x[a-fA-F0-9]{40}$ ]]
then
  echo "Invalid callback specified. Provide the address after the --callback flag."
  exit 1
fi

# Check that the allowlist merkle root is defined and is a bytes32 string
if [[ ! "$allowlistMerkleRoot" =~ ^0x[a-fA-F0-9]{64}$ ]]
then
  echo "Invalid allowlist merkle root specified. Provide the bytes32 string after the --allowlistMerkleRoot flag."
  exit 1
fi

echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"
echo "Using quote token: $quoteToken"
echo "Using base token: $baseToken"
echo "Using callback: $callback"
echo "Using allowlist merkle root: $allowlistMerkleRoot"
echo "Deployer: $DEPLOYER_ADDRESS"

# Set BROADCAST_FLAG based on BROADCAST
BROADCAST_FLAG=""
if [ "$BROADCAST" = "true" ] || [ "$BROADCAST" = "TRUE" ]; then
  BROADCAST_FLAG="--broadcast"
  echo "Broadcast: enabled"
else
  echo "Broadcast: disabled"
fi

# Create auction
forge script ./script/ops/test/FixedPriceBatch/TestData.s.sol:TestData --sig "createAuction(string,address,address,address,bytes32)()" $CHAIN $quoteToken $baseToken $callback $allowlistMerkleRoot \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvvv \
$BROADCAST_FLAG
