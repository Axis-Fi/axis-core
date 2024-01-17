/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {WithModules, Veecode} from "src/modules/Modules.sol";

import {DerivativeModule} from "src/modules/Derivative.sol";

abstract contract Derivatizer is WithModules {
    // ========== DERIVATIVE MANAGEMENT ========== //

    /// @notice         Deploys a new derivative token
    ///
    /// @param          dType           The derivative module code
    /// @param          data            The derivative module parameters
    /// @param          wrapped         Whether or not to wrap the derivative token
    ///
    /// @return         tokenId         The unique derivative token ID
    /// @return         wrappedToken    The wrapped derivative token address (or zero)
    function deploy(
        Veecode dType,
        bytes memory data,
        bool wrapped
    ) external virtual returns (uint256 tokenId, address wrappedToken);

    // function mint(
    //     bytes memory data,
    //     uint256 amount,
    //     bool wrapped
    // ) external virtual returns (bytes memory);
    // function mint(
    //     uint256 tokenId,
    //     uint256 amount,
    //     bool wrapped
    // ) external virtual returns (bytes memory);

    // function redeem(bytes memory data, uint256 amount) external virtual;

    // // function batchRedeem(bytes[] memory data, uint256[] memory amounts) external virtual;

    // function exercise(bytes memory data, uint256 amount) external virtual;

    // function reclaim(bytes memory data) external virtual;

    // function convert(bytes memory data, uint256 amount) external virtual;

    // // TODO Consider best inputs for UX
    // function wrap(uint256 tokenId, uint256 amount) external virtual;
    // function unwrap(uint256 tokenId, uint256 amount) external virtual;

    // // ========== DERIVATIVE INFORMATION ========== //

    // // TODO view function to format implementation specific token data correctly and return to user

    // function exerciseCost(
    //     bytes memory data,
    //     uint256 amount
    // ) external view virtual returns (uint256);

    // function convertsTo(
    //     bytes memory data,
    //     uint256 amount
    // ) external view virtual returns (uint256);

    // // Compute unique token ID for params on the submodule
    // function computeId(bytes memory params_) external pure virtual returns (uint256);
}
