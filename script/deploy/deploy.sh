#!/bin/bash

# Usage:
# ./deploy.sh --deployFile <deploy-file> --broadcast <false> --verify <false> --save <true> --resume <false> --envFile <.env>
#
# Environment variables:
# CHAIN:              Chain name to deploy to. Corresponds to names in "./script/env.json".
# ETHERSCAN_API_KEY:  API key for Etherscan verification. Should be specified in .env.
# RPC_URL:            URL for the RPC node. Should be specified in .env.
# VERIFIER_URL:       URL for the Etherscan API verifier. Should be specified when used on an unsupported chain.

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
DEPLOY_FILE=$deployFile
BROADCAST=${broadcast:-false}
VERIFY=${verify:-false}
SAVE=${save:-true}
RESUME=${resume:-false}

# Check that the CHAIN environment variable is set
if [ -z "$CHAIN" ]
then
  echo "CHAIN environment variable is not set. Please set it in the .env file or provide it as an environment variable."
  exit 1
fi

# Check if DEPLOY_FILE is set
if [ -z "$DEPLOY_FILE" ]
then
  echo "No deploy file specified. Provide the relative path after the --deployFile flag."
  exit 1
fi

# Check if DEPLOY_FILE exists
if [ ! -f "$DEPLOY_FILE" ]
then
  echo "Deploy file ($DEPLOY_FILE) not found. Provide the correct relative path after the --deployFile flag."
  exit 1
fi

# Validate if SAVE is "true" or "false", otherwise throw an error
if [ "$SAVE" != "true" ] && [ "$SAVE" != "false" ]; then
  echo "Invalid value for --save. Use 'true' or 'false'."
  exit 1
fi

# Specify either of these variables to override the defaults
DEPLOY_SCRIPT=${DEPLOY_SCRIPT:-"./script/deploy/Deploy.s.sol"}
DEPLOY_CONTRACT=${DEPLOY_CONTRACT:-"Deploy"}

# If the chain contains "blast", use the Blast-specific contracts to deploy
if [[ $CHAIN == *"blast"* ]]
then
  echo "Using Blast-specific contracts"
  DEPLOY_SCRIPT="./script/deploy/DeployBlast.s.sol"
  DEPLOY_CONTRACT="DeployBlast"
fi

echo "Using deploy script and contract: $DEPLOY_SCRIPT:$DEPLOY_CONTRACT"
echo "Using deployment configuration: $DEPLOY_FILE"
echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"
if [ -n "$VERIFIER_URL" ]; then
  echo "Using verifier at URL: $VERIFIER_URL"
fi
echo "Deployer: $DEPLOYER_ADDRESS"
echo ""

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

# Report if SAVE is enabled
if [ "$SAVE" = "true" ]; then
  echo "Save deployment: enabled"
else
  echo "Save deployment: disabled"
fi

# Set RESUME_FLAG based on RESUME
RESUME_FLAG=""
if [ "$RESUME" = "true" ] || [ "$RESUME" = "TRUE" ]; then
  RESUME_FLAG="--resume"
  echo "Resume: enabled"
else
  echo "Resume: disabled"
fi

# Deploy using script
forge script $DEPLOY_SCRIPT:$DEPLOY_CONTRACT --sig "deploy(string,string,bool)()" $CHAIN $DEPLOY_FILE $SAVE \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
$BROADCAST_FLAG \
$VERIFY_FLAG \
$RESUME_FLAG

# Insert for Mantle deployments
# -g 4000000 --with-gas-price 20000000 --priority-gas-price 10000000 \