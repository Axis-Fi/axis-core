#!/bin/bash

# Usage:
# ./deploy.sh <deploy-file> <broadcast=false> <verify=false>

# TODOs
# [ ] Support alternative Etherscan URLs
# [ ] Support Tenderly verification

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
DEPLOY_FILE=$1
BROADCAST=${2:-false}
VERIFY=${3:-false}

# Check if DEPLOY_FILE is set
if [ -z "$DEPLOY_FILE" ]
then
  echo "No deploy file specified. Provide the relative path after the command."
  exit 1
fi

# Check if DEPLOY_FILE exists
if [ ! -f "$DEPLOY_FILE" ]
then
  echo "Deploy file ($DEPLOY_FILE) not found. Provide the correct relative path after the command."
  exit 1
fi

echo "Using RPC at URL: $RPC_URL"

# Set BROADCAST_FLAG based on BROADCAST
BROADCAST_FLAG=""
if [ "$BROADCAST" = "true" ] || [ "$BROADCAST" = "TRUE" ]; then
  BROADCAST_FLAG="--broadcast"
  echo "Broadcasting is enabled"
else
  echo "Broadcasting is disabled"
fi

# Set VERIFY_FLAG based on VERIFY
VERIFY_FLAG=""
if [ "$VERIFY" = "true" ] || [ "$VERIFY" = "TRUE" ]; then

  # Check if ETHERSCAN_KEY is set
  if [ -z "$ETHERSCAN_KEY" ]
  then
    echo "No Etherscan API key found. Provide the key in .env or disable verification."
    exit 1
  fi

  VERIFY_FLAG="--verify --etherscan-api-key $ETHERSCAN_KEY"
  echo "Verification is enabled"
else
  echo "Verification is disabled"
fi

# Deploy using script
forge script ./script/deploy/Deploy.s.sol:Deploy --sig "deploy(string,string)()" $CHAIN $DEPLOY_FILE \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
$BROADCAST_FLAG \
$VERIFY_FLAG \
