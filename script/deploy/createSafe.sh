# Load environment variables
source .env

# Deploy the safe using calculated calldata
cast send --private-key=$DEPLOYER_PRIVATE_KEY --rpc-url=$RPC_URL --from=$DEPLOYER_ADDRESS \
   $SAFE_FACTORY_ADDRESS $SAFE_CALLDATA