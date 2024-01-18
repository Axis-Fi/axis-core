// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {DerivativeModule} from "src/modules/Derivative.sol";

import {MockERC6909} from "solmate/test/utils/mocks/MockERC6909.sol";
import {MockWrappedDerivative} from "test/lib/mocks/MockWrappedDerivative.sol";

contract MockDerivativeModule is DerivativeModule {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;

    bool internal validateFails;
    MockERC6909 public derivativeToken;
    uint256 internal tokenCount;
    MockWrappedDerivative internal wrappedImplementation;

    error InvalidDerivativeParams();

    struct DeployParams {
        address collateralToken;
    }

    struct MintParams {
        uint256 tokenId;
        uint256 multiplier;
    }

    constructor(address _owner) Module(_owner) {
        derivativeToken = new MockERC6909();
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("DERV"), 1);
    }

    function TYPE() public pure virtual override returns (Type) {
        return Type.Derivative;
    }

    function deploy(
        bytes memory params_,
        bool wrapped_
    ) external virtual override returns (uint256, address) {
        uint256 tokenId = tokenCount;
        address wrappedAddress;

        // Check length
        if (params_.length != 32) revert InvalidDerivativeParams();

        // Decode params
        DeployParams memory decodedParams = abi.decode(params_, (DeployParams));
        if (decodedParams.collateralToken == address(0)) revert InvalidDerivativeParams();

        if (wrapped_) {
            // If there is no wrapped implementation, abort
            if (address(wrappedImplementation) == address(0)) revert("");

            // Deploy the wrapped implementation
            wrappedAddress = address(wrappedImplementation).clone3(
                abi.encodePacked(derivativeToken, tokenId), bytes32(tokenId)
            );
        }

        // Create new token metadata
        Token memory tokenData = Token({
            exists: true,
            wrapped: wrappedAddress,
            decimals: 18,
            name: "Mock Derivative",
            symbol: "MDER",
            data: params_ // Should collateralToken be present on every set of metadata?
        });

        // Store metadata
        tokenMetadata[tokenId] = tokenData;

        tokenCount++;

        return (tokenId, wrappedAddress);
    }

    function mint(
        address to_,
        bytes memory params_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {
        if (params_.length != 64) revert("");

        // TODO this should be deploying a new derivative token if it doesn't exist

        MintParams memory params = abi.decode(params_, (MintParams));

        // Check that tokenId exists
        Token storage token = tokenMetadata[params.tokenId];
        if (!token.exists) revert("");

        // Check that the wrapped status is correct
        if (token.wrapped != address(0) && !wrapped_) revert("");

        // Decode extra token data
        DeployParams memory decodedParams = abi.decode(token.data, (DeployParams));

        // Transfer collateral token to this contract
        ERC20(decodedParams.collateralToken).safeTransferFrom(msg.sender, address(this), amount_);

        uint256 outputAmount = params.multiplier == 0 ? amount_ : amount_ * params.multiplier;

        // If wrapped, mint and deposit
        if (wrapped_) {
            derivativeToken.mint(address(this), params.tokenId, outputAmount);

            derivativeToken.approve(token.wrapped, params.tokenId, outputAmount);

            MockWrappedDerivative(token.wrapped).deposit(outputAmount, to_);
        }
        // Otherwise mint as normal
        else {
            derivativeToken.mint(to_, params.tokenId, outputAmount);
        }

        return (params.tokenId, token.wrapped, outputAmount);
    }

    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {}

    function redeem(uint256 tokenId_, uint256 amount_, bool wrapped_) external virtual override {}

    function exercise(uint256 tokenId_, uint256 amount, bool wrapped_) external virtual override {}

    function reclaim(uint256 tokenId_) external virtual override {}

    function transform(
        uint256 tokenId_,
        address from_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override {}

    function wrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function unwrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function exerciseCost(
        bytes memory data,
        uint256 amount
    ) external view virtual override returns (uint256) {}

    function convertsTo(
        bytes memory data,
        uint256 amount
    ) external view virtual override returns (uint256) {}

    function computeId(bytes memory params_) external pure virtual override returns (uint256) {}

    function validate(bytes memory) external view virtual override returns (bool) {
        if (validateFails) revert("validation error");

        return true;
    }

    function setValidateFails(bool validateFails_) external {
        validateFails = validateFails_;
    }

    function setWrappedImplementation(MockWrappedDerivative implementation_) external {
        wrappedImplementation = implementation_;
    }
}
