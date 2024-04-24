#!/bin/bash

echo "*** Installing dependencies using pnpm" 
pnpm install

echo "*** Setting up submodules"
git submodule init
git submodule update

echo "*** Running forge install"
forge install

echo "*** Restoring submodule commits"
# Lock the submodules to specific commits
cd lib/forge-std/ && git checkout v1.7.1  && cd ../..
cd lib/prb-math/ && git checkout v4.0.2 && cd ../..
cd lib/solady/ && git checkout v0.0.124 && cd ../..
cd lib/solmate/ && git checkout c892309933b25c03d32b1b0d674df7ae292ba925 && cd ../..

echo "*** Running forge build"
forge build
