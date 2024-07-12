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
