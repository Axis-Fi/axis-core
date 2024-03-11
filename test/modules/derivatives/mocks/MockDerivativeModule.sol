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

    bool internal _validateFails;
    MockERC6909 public derivativeToken;
    MockWrappedDerivative internal _wrappedImplementation;

    error InvalidDerivativeParams();

    struct DerivativeParams {
        uint48 expiry;
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
        address underlyingToken_,
        bytes memory params_,
        bool wrapped_
    ) external virtual override returns (uint256, address) {
        if (underlyingToken_ == address(0)) revert InvalidDerivativeParams();

        // Check length
        if (params_.length != 64) revert InvalidDerivativeParams();

        // Decode params
        DerivativeParams memory decodedParams = abi.decode(params_, (DerivativeParams));

        (uint256 tokenId, address wrappedAddress) =
            _deployIfNeeded(underlyingToken_, decodedParams, wrapped_);
        return (tokenId, wrappedAddress);
    }

    function mint(
        address to_,
        address underlyingToken_,
        bytes memory params_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {
        if (params_.length != 64) revert("");

        DerivativeParams memory decodedParams = abi.decode(params_, (DerivativeParams));

        // Deploy if needed
        (uint256 tokenId, address wrappedAddress) =
            _deployIfNeeded(underlyingToken_, decodedParams, wrapped_);

        // Check that the wrapped status is correct
        if (wrappedAddress != address(0) && !wrapped_) revert("");

        // Transfer collateral token to this contract
        ERC20(underlyingToken_).safeTransferFrom(msg.sender, address(this), amount_);

        uint256 outputAmount =
            decodedParams.multiplier == 0 ? amount_ : amount_ * decodedParams.multiplier;

        // If wrapped, mint and deposit
        if (wrapped_) {
            derivativeToken.mint(address(this), tokenId, outputAmount);

            derivativeToken.approve(wrappedAddress, tokenId, outputAmount);

            MockWrappedDerivative(wrappedAddress).deposit(outputAmount, to_);
        }
        // Otherwise mint as normal
        else {
            derivativeToken.mint(to_, tokenId, outputAmount);
        }

        return (tokenId, wrappedAddress, outputAmount);
    }

    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {}

    function redeem(uint256 tokenId_, uint256 amount_) external virtual override {}

    function exercise(uint256 tokenId_, uint256 amount) external virtual override {}

    function reclaim(uint256 tokenId_) external virtual override {}

    function transform(
        uint256 tokenId_,
        address from_,
        uint256 amount_
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

    function computeId(
        address underlyingToken_,
        bytes memory params_
    ) external pure virtual override returns (uint256) {}

    function validate(address, bytes memory) external view virtual override returns (bool) {
        if (_validateFails) revert("validation error");

        return true;
    }

    function setValidateFails(bool validateFails_) external {
        _validateFails = validateFails_;
    }

    function setWrappedImplementation(MockWrappedDerivative implementation_) external {
        _wrappedImplementation = implementation_;
    }

    function _computeId(ERC20 base_, uint48 expiry_) internal pure returns (uint256) {
        return
            uint256(keccak256(abi.encodePacked(VEECODE(), keccak256(abi.encode(base_, expiry_)))));
    }

    function _getNameAndSymbol(
        ERC20 base_,
        uint48 expiry_
    ) internal view returns (string memory, string memory) {
        return (
            string(abi.encodePacked(base_.name(), "-", expiry_)),
            string(abi.encodePacked(base_.symbol(), "-", expiry_))
        );
    }

    function _deployIfNeeded(
        address underlyingToken_,
        DerivativeParams memory params_,
        bool wrapped_
    ) internal returns (uint256, address) {
        address wrappedAddress;

        // Generate the token id
        uint256 tokenId = _computeId(ERC20(underlyingToken_), params_.expiry);

        // Check if the derivative exists
        Token storage token = tokenMetadata[tokenId];
        if (!token.exists) {
            if (wrapped_) {
                // If there is no wrapped implementation, abort
                if (address(_wrappedImplementation) == address(0)) revert("");

                // Deploy the wrapped implementation
                wrappedAddress = address(_wrappedImplementation).clone3(
                    abi.encodePacked(derivativeToken, tokenId), bytes32(tokenId)
                );
                token.wrapped = wrappedAddress;
            }

            // Store derivative data
            token.exists = true;
            token.underlyingToken = underlyingToken_;
            token.data = abi.encode(params_);

            // Store metadata
            tokenMetadata[tokenId] = token;
        }

        return (tokenId, token.wrapped);
    }

    function redeemMax(uint256 tokenId_) external virtual override {}

    function redeemable(
        address owner_,
        uint256 tokenId_
    ) external view virtual override returns (uint256) {}

    function name(uint256 tokenId_) public view virtual override returns (string memory) {}

    function symbol(uint256 tokenId_) public view virtual override returns (string memory) {}

    function decimals(uint256 tokenId_) public view virtual override returns (uint8) {}
}
