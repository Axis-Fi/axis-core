/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {AuctionHouse} from "src/AuctionHouse.sol";
import {Veecode} from "src/modules/Modules.sol";

enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
}

interface IBlast {
    function configureClaimableGas() external;
    function claimMaxGas(
        address contractAddress,
        address recipientOfGas
    ) external returns (uint256);
}

interface IERC20Rebasing {
    // changes the yield mode of the caller and update the balance
    // to reflect the configuration
    function configure(YieldMode) external returns (uint256);
    // "claimable" yield mode accounts can call this this claim their yield
    // to another address
    function claim(address recipient, uint256 amount) external returns (uint256);
    // read the claimable amount for an account
    function getClaimableAmount(address account) external view returns (uint256);
}

contract BlastAuctionHouse is AuctionHouse {
    // ========== STATE VARIABLES ========== //

    /// @notice    Blast contract for claiming gas fees
    IBlast internal constant _BLAST = IBlast(0x4300000000000000000000000000000000000002);

    /// @notice    Address of the WETH contract on Blast
    IERC20Rebasing internal constant _WETH =
        IERC20Rebasing(0x4200000000000000000000000000000000000023);

    /// @notice    Address of the USDB contract on Blast
    IERC20Rebasing internal constant _USDB =
        IERC20Rebasing(0x4200000000000000000000000000000000000022);

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_
    ) AuctionHouse(owner_, protocol_, permit2_) {
        // Set the yield mode to claimable for the WETH and USDB tokens
        _WETH.configure(YieldMode.CLAIMABLE);
        _USDB.configure(YieldMode.CLAIMABLE);

        // Set gas fees to claimable
        _BLAST.configureClaimableGas();
    }

    // ========== CLAIM FUNCTIONS ========== //

    function claimYieldAndGas() external {
        // Claim the yield for the WETH and USDB tokens and send to protocol
        _WETH.claim(_protocol, _WETH.getClaimableAmount(address(this)));
        _USDB.claim(_protocol, _USDB.getClaimableAmount(address(this)));

        // Claim the gas consumed by this contract, send to protocol
        _BLAST.claimMaxGas(address(this), _protocol);
    }

    function claimModuleGas(Veecode reference_) external {
        // Claim the gas consumed by the module, send to protocol
        _BLAST.claimMaxGas(address(_getModuleIfInstalled(reference_)), _protocol);
    }
}
