// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {FeeCalculatorBase} from './FeeCalculatorBase.sol';
import {IFeeCalculator} from '../interfaces/fees/IFeeCalculator.sol';
import {IParam} from '../interfaces/IParam.sol';

/// @title TransferFrom fee calculator for ERC20::transferFrom
/// @dev Cause a failed transaction when the rarely used ERC721::transferFrom is executed
contract TransferFromFeeCalculator is IFeeCalculator, FeeCalculatorBase {
    bytes32 internal constant _META_DATA = bytes32(bytes('erc20:transfer-from'));

    constructor(address router_, uint256 feeRate_) FeeCalculatorBase(router_, feeRate_) {}

    function getFees(address to, bytes calldata data) external view returns (IParam.Fee[] memory) {
        // Token transfrom signature:'transferFrom(address,address,uint256)', selector:0x23b872dd
        (, , uint256 amount) = abi.decode(data[4:], (address, address, uint256));

        IParam.Fee[] memory fees = new IParam.Fee[](1);
        fees[0] = IParam.Fee({token: to, amount: calculateFee(amount), metadata: _META_DATA});
        return fees;
    }

    function getDataWithFee(bytes calldata data) external view returns (bytes memory) {
        (address from, address to, uint256 amount) = abi.decode(data[4:], (address, address, uint256));
        amount = calculateAmountWithFee(amount);
        return abi.encodePacked(data[:4], abi.encode(from, to, amount));
    }
}
