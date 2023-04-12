// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SafeERC20, IERC20, Address} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IAgent} from '../interfaces/IAgent.sol';
import {IRouter} from '../interfaces/IRouter.sol';
import {IAaveV3FlashLoanCallback} from '../interfaces/IAaveV3FlashLoanCallback.sol';
import {IAaveV3Provider} from '../interfaces/aaveV3/IAaveV3Provider.sol';
import {ApproveHelper} from '../libraries/ApproveHelper.sol';

/// @title Aave V3 flash loan callback
contract AaveV3FlashLoanCallback is IAaveV3FlashLoanCallback {
    using SafeERC20 for IERC20;
    using Address for address;

    address public immutable router;
    address public immutable aaveV3Provider;

    constructor(address router_, address aaveV3Provider_) {
        router = router_;
        aaveV3Provider = aaveV3Provider_;
    }

    /// @dev No need to check whether `initiator` is Agent as it's certain when the below conditions are satisfied:
    ///      1. `to` in Agent is Aave Pool, i.e, user signed a correct `to`
    ///      2. `_callback` in Agent is set to this callback, i.e, user signed a correct `callback`
    ///      3. `msg.sender` of this callback is Aave Pool
    ///      4. Aave Pool contract is benign
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address, // initiator
        bytes calldata params
    ) external returns (bool) {
        address pool = IAaveV3Provider(aaveV3Provider).getPool();

        if (msg.sender != pool) revert InvalidCaller();
        address agent = IRouter(router).getAgent();

        // Transfer assets to Agent and record initial balances
        uint256 assetsLength = assets.length;
        uint256[] memory initBalances = new uint256[](assetsLength);
        for (uint256 i = 0; i < assetsLength; ) {
            address asset = assets[i];

            IERC20(asset).safeTransfer(agent, amounts[i]);
            initBalances[i] = IERC20(asset).balanceOf(address(this));

            unchecked {
                ++i;
            }
        }

        agent.functionCall(abi.encodePacked(IAgent.execute.selector, params), 'ERROR_AAVE_V3_FLASH_LOAN_CALLBACK');

        // Approve assets for pulling from Aave Pool
        for (uint256 i = 0; i < assetsLength; ) {
            address asset = assets[i];
            uint256 amountOwing = amounts[i] + premiums[i];

            // Check balance is valid
            if (IERC20(asset).balanceOf(address(this)) != initBalances[i] + amountOwing) revert InvalidBalance(asset);

            // Save gas by only the first user does approve. It's safe since this callback don't hold any asset
            ApproveHelper._approveMax(asset, pool, amountOwing);

            unchecked {
                ++i;
            }
        }

        return true;
    }
}
