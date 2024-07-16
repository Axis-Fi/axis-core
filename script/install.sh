#!/bin/bash

# echo ""
# echo "*** Setting up submodules"
# git submodule init
# git submodule update
# echo "    Done"

echo ""
echo "*** Installing forge dependencies"
forge install
echo "    Done"

echo ""
echo "*** Installing soldeer dependencies"
rm -rf dependencies/* && forge soldeer update
echo "    Done"

# echo ""
# echo "*** Restoring submodule commits"
# echo "    Done"
