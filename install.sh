#!/bin/bash

echo "*** Installing dependencies using pnpm"
pnpm install

echo ""
echo "*** Setting up submodules"
git submodule init
git submodule update

echo ""
echo "*** Running forge install"
forge install

echo ""
echo "*** Restoring submodule commits"
# Lock the submodules to specific commits
echo ""
echo "forge-std"
cd lib/forge-std/ && git checkout v1.7.1  && cd ../..

echo ""
echo "prb-math"
cd lib/prb-math/ && git checkout v4.0.2 && cd ../..

echo ""
echo "solady"
cd lib/solady/ && git checkout v0.0.124 && cd ../..

echo ""
echo "solmate"
cd lib/solmate/ && git checkout c892309933b25c03d32b1b0d674df7ae292ba925 && cd ../..

echo ""
echo "openzeppelin-contracts"
cd lib/openzeppelin-contracts && git checkout d6b63a48ba440ad8d551383697db6e5b0ef84137 && cd ../..

echo ""
echo "openzeppelin-contracts-upgradeable"
cd lib/openzeppelin-contracts-upgradeable && git checkout dda4972793c55bfdae604e8ef3388352e3e34bf1 && cd ../..

echo ""
echo "uniswap-v2-core"
cd lib/uniswap-v2-core && git checkout v1.0.1 && cd ../..

echo ""
echo "uniswap-v3-core"
cd lib/uniswap-v3-core && git checkout 6562c52e8f75f0c10f9deaf44861847585fc8129 && cd ../..

echo ""
echo "uniswap-v3-periphery"
cd lib/uniswap-v3-periphery && git checkout b325bb0905d922ae61fcc7df85ee802e8df5e96c && cd ../..

echo ""
echo "*** Running forge build"
forge build
