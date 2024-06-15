#!/bin/bash

# Usage:
# ./placeBid.sh --lotId <uint96> --amount <uint256> --envFile <.env>
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

# Check that the lotId is defined and is an integer
if [[ ! "$lotId" =~ ^[0-9]+$ ]]
then
  echo "Invalid lotId specified. Provide the integer value after the --lotId flag."
  exit 1
fi

# Check that the amount is defined and is an integer
if [[ ! "$amount" =~ ^[0-9]+$ ]]
then
  echo "Invalid amount specified. Provide the integer value after the --amount flag."
  exit 1
fi

# Check that the merkle proof is defined and is a bytes32 string
if [[ ! "$merkleProof" =~ ^0x[a-fA-F0-9]{64}$ ]]
then
  echo "Invalid merkle proof specified. Provide the bytes32 string after the --merkleProof flag."
  exit 1
fi

# Check that the allocated amount is defined and is an integer
if [[ ! "$allocatedAmount" =~ ^[0-9]+$ ]]
then
  echo "Invalid allocated amount specified. Provide the integer value after the --allocatedAmount flag."
  exit 1
fi

echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"
echo "Lot ID: $lotId"
echo "Amount: $amount"
echo "Merkle proof: $merkleProof"
echo "Allocated amount: $allocatedAmount"
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
forge script ./script/ops/test/FixedPriceBatch/TestData.s.sol:TestData --sig "placeBid(string,uint96,uint256,bytes32,uint256)()" $CHAIN $lotId $amount $merkleProof $allocatedAmount \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvvv \
$BROADCAST_FLAG
