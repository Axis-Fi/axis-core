#!/bin/bash

# Usage:
# ./deployTokens.sh --seller <seller> --buyer <buyer> --envFile <.env> --broadcast <false> --verify <false> --resume <false>

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
VERIFY=${verify:-false}
RESUME=${resume:-false}

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
if [ -n "$VERIFIER_URL" ]; then
  echo "Using verifier at URL: $VERIFIER_URL"
fi
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

# Set VERIFY_FLAG based on VERIFY
VERIFY_FLAG=""
if [ "$VERIFY" = "true" ] || [ "$VERIFY" = "TRUE" ]; then

  if [ -z "$VERIFIER" ] || [ "$VERIFIER" = "etherscan" ]; then
    # Check if ETHERSCAN_API_KEY is set
    if [ -z "$ETHERSCAN_API_KEY" ]; then
      echo "No Etherscan API key found. Provide the key in .env or disable verification."
      exit 1
    fi

    if [ -n "$VERIFIER_URL" ]; then
      VERIFY_FLAG="--verify --verifier-url $VERIFIER_URL --etherscan-api-key $ETHERSCAN_API_KEY"
    else
      VERIFY_FLAG="--verify --etherscan-api-key $ETHERSCAN_API_KEY"
    fi
  else
    if [ -n "$VERIFIER_URL" ]; then
      VERIFY_FLAG="--verify --verifier $VERIFIER --verifier-url $VERIFIER_URL"
    else
      VERIFY_FLAG="--verify --verifier $VERIFIER"
    fi
  fi
  echo "Verification: enabled"
else
  echo "Verification: disabled"
fi

# Set RESUME_FLAG based on RESUME
RESUME_FLAG=""
if [ "$RESUME" = "true" ] || [ "$RESUME" = "TRUE" ]; then
  RESUME_FLAG="--resume"
  echo "Resume: enabled"
else
  echo "Resume: disabled"
fi

# Create auction
forge script ./script/ops/test/TestData.s.sol:TestData --sig "deployTestTokens(address,address)()" $seller $buyer \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
$BROADCAST_FLAG \
$VERIFY_FLAG \
$RESUME_FLAG
