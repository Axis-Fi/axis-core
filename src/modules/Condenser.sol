// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {ICondenser} from "src/interfaces/ICondenser.sol";

import {Module} from "src/modules/Modules.sol";

abstract contract CondenserModule is ICondenser, Module {}
