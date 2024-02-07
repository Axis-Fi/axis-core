/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {AuctionHouse} from "src/AuctionHouse.sol";
import {BlastGas, IBlast} from "src/blast/modules/BlastGas.sol";
import {Veecode, wrapVeecode} from "src/modules/Modules.sol";

enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
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
    IERC20Rebasing internal _weth;

    /// @notice    Address of the USDB contract on Blast
    IERC20Rebasing internal _usdb;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address permit2_,
        address weth_,
        address usdb_
    ) AuctionHouse(owner_, permit2_) {
        _weth = IERC20Rebasing(weth_);
        _usdb = IERC20Rebasing(usdb_);

        // Set the yield mode to claimable for the WETH and USDB tokens
        _weth.configure(YieldMode.CLAIMABLE);
        _usdb.configure(YieldMode.CLAIMABLE);

        // Set gas fees to claimable
        _BLAST.configureClaimableGas();
    }

    // ========== CLAIM FUNCTIONS ========== //

    function claimYieldAndGas() external onlyOwner {
        // Claim the yield for the WETH and USDB tokens and send to protocol
        uint256 wethClaimable = _weth.getClaimableAmount(address(this));
        uint256 usdbClaimable = _usdb.getClaimableAmount(address(this));

        if (wethClaimable > 0) _weth.claim(_protocol, wethClaimable);
        if (usdbClaimable > 0) _usdb.claim(_protocol, usdbClaimable);

        // Claim the gas consumed by this contract, send to protocol
        _BLAST.claimMaxGas(address(this), _protocol);

        // Iterate through modules and claim gas for each
        uint256 len = modules.length;
        for (uint256 i = 0; i < len; i++) {
            ModStatus memory status = getModuleStatus[modules[i]];
            if (status.sunset) continue;

            Veecode veecode = wrapVeecode(modules[i], status.latestVersion);

            BlastGas(address(getModuleForVeecode[veecode])).claimGas(_protocol);
        }
    }
}
