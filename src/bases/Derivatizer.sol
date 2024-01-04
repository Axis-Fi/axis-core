/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "src/modules/Derivative.sol";

abstract contract Derivatizer is WithModules {
    // ========== DERIVATIVE MANAGEMENT ========== //

    // Return address will be zero if not wrapped
    function deploy(
        Keycode dType,
        bytes memory data,
        bool wrapped
    ) external virtual returns (uint256, address) {
        // Load the derivative module, will revert if not installed
        Derivative derivative = Derivative(address(_getLatestModuleIfActive(dType)));

        // Check that the type hasn't been sunset
        ModStatus storage moduleStatus = getModuleStatus[dType];
        if (moduleStatus.sunset) revert("Derivatizer: type sunset");

        // Call the deploy function on the derivative module
        (uint256 tokenId, address wrappedToken) = derivative.deploy(data, wrapped);

        return (tokenId, wrappedToken);
    }

    function mint(
        bytes memory data,
        uint256 amount,
        bool wrapped
    ) external virtual returns (bytes memory);
    function mint(
        uint256 tokenId,
        uint256 amount,
        bool wrapped
    ) external virtual returns (bytes memory);

    function redeem(bytes memory data, uint256 amount) external virtual;

    // function batchRedeem(bytes[] memory data, uint256[] memory amounts) external virtual;

    function exercise(bytes memory data, uint256 amount) external virtual;

    function reclaim(bytes memory data) external virtual;

    function convert(bytes memory data, uint256 amount) external virtual;

    // TODO Consider best inputs for UX
    function wrap(uint256 tokenId, uint256 amount) external virtual;
    function unwrap(uint256 tokenId, uint256 amount) external virtual;

    // ========== DERIVATIVE INFORMATION ========== //

    // TODO view function to format implementation specific token data correctly and return to user

    function exerciseCost(
        bytes memory data,
        uint256 amount
    ) external view virtual returns (uint256);

    function convertsTo(bytes memory data, uint256 amount) external view virtual returns (uint256);

    // Compute unique token ID for params on the submodule
    function computeId(bytes memory params_) external pure virtual returns (uint256);
}
