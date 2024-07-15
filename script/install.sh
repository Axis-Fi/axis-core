#!/bin/bash

echo ""
echo "*** Setting up submodules"
git submodule init
git submodule update

echo ""
echo "*** Installing forge dependencies"
forge install

echo ""
echo "*** Installing soldeer dependencies"
forge soldeer update

echo ""
echo "*** Restoring submodule commits"
echo "    Done"
