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
echo "solady"
cd lib/solady/ && git checkout v0.0.124 && cd ../..

echo ""
echo "solmate"
cd lib/solmate/ && git checkout c892309933b25c03d32b1b0d674df7ae292ba925 && cd ../..

echo ""
echo "*** Running forge build"
forge build
