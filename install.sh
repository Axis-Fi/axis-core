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
echo "*** Installing soldeer dependencies"
forge soldeer update

echo ""
echo "*** Restoring submodule commits"

echo ""
echo "*** Running forge build"
forge build
