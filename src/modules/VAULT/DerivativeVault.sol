/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "src/modules/VAULT/VAULT.v1.sol";

contract DerivativeVault is VAULTv1 {


    /// @inheritdoc VAULTv1
    function deploy(SubKeycode dType_, bytes memory params_, bool wrapped_) external returns (uint256) {
        // Get submodule, reverts if not installed
        address submodule = address(_getSubmoduleIfInstalled(dType_));

        // Delegate call to submodule
        // This pattern depends on the storage slots of the module and submodules being same for the referenced slots.
        // All VAULT submodules must have VaultStorage and ERC6909 as their first two parents.
        (bool success, bytes memory data) = submodule.delegatecall(abi.encodeWithSelector(VaultSubmodule.deploy.selector, params_, wrapped_));

        // Revert if call failed
        if (!success) revert VAULT_SubmoduleExecutionReverted(data);

        // Otherwise, return
        return abi.decode(data, (uint256));
    }
}