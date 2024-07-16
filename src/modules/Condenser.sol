// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {ICondenser} from "../interfaces/modules/ICondenser.sol";

import {Module} from "./Modules.sol";

/// @title  CondenserModule
/// @notice The CondenserModule contract is an abstract contract that provides condenser functionality for the AuctionHouse.
/// @dev    This contract is intended to be inherited by condenser modules that are used in the AuctionHouse.
abstract contract CondenserModule is ICondenser, Module {}
