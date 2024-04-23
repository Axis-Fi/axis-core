#!/bin/bash

# Usage:
# ./deploy.sh <deploy-file> <broadcast=false> <verify=false> <resume=false>
#
# Environment variables:
# CHAIN:              Chain name to deploy to. Corresponds to names in "./script/env.json".
# DEPLOY_SCRIPT:      Path to the Forge deploy script. Defaults to "./script/deploy/Deploy.s.sol".
# DEPLOY_CONTRACT:    Contract name in the deploy script. Defaults to "Deploy".
# ETHERSCAN_KEY:      API key for Etherscan verification. Should be specified in .env.
# RPC_URL:            URL for the RPC node. Should be specified in .env.
# VERIFIER_URL:       URL for the Etherscan API verifier. Should be specified when used on an unsupported chain.

# TODOs
# [X] Support alternative Etherscan URLs
# [ ] Support Tenderly verification
# [X] Override use of Deploy.s.sol:Deploy with a different script

# Specify either of these variables to override the defaults
DEPLOY_SCRIPT=${DEPLOY_SCRIPT:-"./script/deploy/Deploy.s.sol"}
DEPLOY_CONTRACT=${DEPLOY_CONTRACT:-"Deploy"}

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
DEPLOY_FILE=$1
BROADCAST=${2:-false}
VERIFY=${3:-false}
RESUME=${4:-false}

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

echo "Using deploy script and contract: $DEPLOY_SCRIPT:$DEPLOY_CONTRACT"
echo "Using deployment configuration: $DEPLOY_FILE"
echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"
if [ -n "$VERIFIER_URL" ]; then
  echo "Using verifier at URL: $VERIFIER_URL"
fi
echo "Deployer: $DEPLOYER_ADDRESS"
echo ""

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

# Set RESUME_FLAG based on RESUME
RESUME_FLAG=""
if [ "$RESUME" = "true" ] || [ "$RESUME" = "TRUE" ]; then
  RESUME_FLAG="--resume"
  echo "Resuming is enabled"
else
  echo "Resuming is disabled"
fi

# Deploy using script
forge script $DEPLOY_SCRIPT:$DEPLOY_CONTRACT --sig "deploy(string,string)()" $CHAIN $DEPLOY_FILE \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
$BROADCAST_FLAG \
$VERIFY_FLAG \
$RESUME_FLAG
