#!/bin/bash

# Usage:
# ./deployTokens.sh --seller <seller> --buyer <buyer> --envFile <.env> --broadcast <false>

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

# Check that the seller is defined and is an address
if [[ ! "$seller" =~ ^0x[a-fA-F0-9]{40}$ ]]
then
  echo "Invalid seller specified. Provide the address after the --seller flag."
  exit 1
fi

# Check that the buyer is defined and is an address
if [[ ! "$buyer" =~ ^0x[a-fA-F0-9]{40}$ ]]
then
  echo "Invalid buyer specified. Provide the address after the --buyer flag."
  exit 1
fi

echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"
echo "Seller: $seller"
echo "Buyer: $buyer"
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
forge script ./script/ops/test/TestData.s.sol:TestData --sig "deployTestTokens(address,address)()" $seller $buyer \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
$BROADCAST_FLAG
