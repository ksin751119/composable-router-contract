// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IParam} from '../interfaces/IParam.sol';
import {IFeeCalculator} from '../interfaces/IFeeCalculator.sol';

abstract contract FeeVerifier is Ownable {
    error LengthMismatch();

    event FeeCalculatorSet(bytes4 indexed selector, address indexed to, address indexed feeCalculator);

    address internal constant _NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant _DUMMY_TO_ADDRESS = address(0);
    bytes4 internal constant _NATIVE_FEE_SELECTOR = 0xeeeeeeee;

    mapping(bytes4 selector => mapping(address to => address feeCalculator)) public feeCalculators;

    /// @notice Get logics, msg.value and fees that contains fee
    function getLogicsAndFees(
        IParam.Logic[] memory logics,
        uint256 msgValue
    ) external view returns (IParam.Logic[] memory, uint256, IParam.Fee[] memory) {
        // Update logics
        logics = getLogicsDataWithFee(logics);

        // Update value
        msgValue = getMsgValueWithFee(msgValue);

        // Get fees
        IParam.Fee[] memory fees = getFeesByLogics(logics, msgValue);

        return (logics, msgValue, fees);
    }

    function getLogicsDataWithFee(IParam.Logic[] memory logics) public view returns (IParam.Logic[] memory) {
        uint256 length = logics.length;
        for (uint256 i = 0; i < length; ) {
            bytes memory data = logics[i].data;
            bytes4 selector = bytes4(data);
            address to = logics[i].to;
            address feeCalculator = getFeeCalculator(selector, to);

            // Get transaction data with fee
            if (feeCalculator != address(0)) {
                logics[i].data = IFeeCalculator(feeCalculator).getDataWithFee(data);
            }

            unchecked {
                ++i;
            }
        }

        return logics;
    }

    function getMsgValueWithFee(uint256 msgValue) public view returns (uint256) {
        IFeeCalculator nativeFeeCalculator = getNativeFeeCalculator();
        if (msgValue > 0 && address(nativeFeeCalculator) != address(0)) {
            msgValue = uint256(bytes32(nativeFeeCalculator.getDataWithFee(abi.encodePacked(msgValue))));
        }
        return msgValue;
    }

    function getFeesByLogics(IParam.Logic[] memory logics, uint256 msgValue) public view returns (IParam.Fee[] memory) {
        IParam.Fee[] memory tempFees = new IParam.Fee[](32); // Create a temporary `tempFees` with size 32 to store fee
        uint256 realFeeLength;
        uint256 logicsLength = logics.length;
        for (uint256 i = 0; i < logicsLength; ) {
            bytes memory data = logics[i].data;
            bytes4 selector = bytes4(data);
            address to = logics[i].to;

            // Get feeCalculator
            address feeCalculator = getFeeCalculator(selector, to);
            if (feeCalculator == address(0)) continue; // No need to charge fee

            // Get charge tokens and amounts
            IParam.Fee[] memory feesByLogic = IFeeCalculator(feeCalculator).getFees(to, data);
            uint256 feesByLogicLength = feesByLogic.length;
            if (feesByLogicLength == 0) {
                continue; // No need to charge fee
            }

            for (uint256 feeIndex = 0; feeIndex < feesByLogicLength; ) {
                tempFees[realFeeLength++] = feesByLogic[feeIndex];

                unchecked {
                    ++feeIndex;
                }
            }

            unchecked {
                ++i;
            }
        }

        // For native fee
        IFeeCalculator nativeFeeCalculator = getNativeFeeCalculator();
        if (msgValue > 0 && address(nativeFeeCalculator) != address(0)) {
            tempFees[realFeeLength++] = nativeFeeCalculator.getFees(_DUMMY_TO_ADDRESS, abi.encodePacked(msgValue))[0];
        }

        // Copy tempFees to fees
        IParam.Fee[] memory fees = new IParam.Fee[](realFeeLength);
        for (uint256 i = 0; i < realFeeLength; ) {
            fees[i] = tempFees[i];

            unchecked {
                ++i;
            }
        }

        return fees;
    }

    function verifyFees(
        IParam.Logic[] calldata logics,
        uint256 msgValue,
        IParam.Fee[] memory fees
    ) public view returns (bool) {
        uint256 feesLength = fees.length;
        uint256 logicsLength = logics.length;
        for (uint256 i = 0; i < logicsLength; ) {
            bytes memory data = logics[i].data;
            address to = logics[i].to;
            bytes4 selector = bytes4(data);

            // Get feeCalculator
            address feeCalculator = getFeeCalculator(selector, to);
            if (feeCalculator == address(0)) continue; // No need to charge fee

            // Get charge tokens and amounts
            IParam.Fee[] memory feesByLogic = IFeeCalculator(feeCalculator).getFees(to, data);
            uint256 feesByLogicLength = feesByLogic.length;

            // Deduct all fee from fees
            for (uint256 j = 0; j < feesByLogicLength; ) {
                for (uint256 feesIndex = 0; feesIndex < feesLength; ) {
                    if (feesByLogic[j].token == fees[feesIndex].token) {
                        if (feesByLogic[j].amount > fees[feesIndex].amount) {
                            feesByLogic[j].amount -= fees[feesIndex].amount;
                            fees[feesIndex].amount = 0;
                        } else {
                            fees[feesIndex].amount -= feesByLogic[j].amount;
                            feesByLogic[j].amount = 0;
                            break;
                        }
                    }

                    unchecked {
                        ++feesIndex;
                    }
                }

                // Make sure feesByLogic.amount equals 0
                if (feesByLogic[j].amount > 0) return false;

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Deduct native fee from fees
        IFeeCalculator nativeFeeCalculator = getNativeFeeCalculator();
        if (msgValue > 0 && address(nativeFeeCalculator) != address(0)) {
            uint256 nativeFee = nativeFeeCalculator.getFees(_DUMMY_TO_ADDRESS, abi.encodePacked(msgValue))[0].amount;
            for (uint256 feesIndex = 0; feesIndex < feesLength; ) {
                if (fees[feesIndex].token == _NATIVE) {
                    if (nativeFee > fees[feesIndex].amount) {
                        nativeFee -= fees[feesIndex].amount;
                        fees[feesIndex].amount = 0;
                    } else {
                        fees[feesIndex].amount -= nativeFee;
                        nativeFee = 0;
                        break;
                    }
                }

                unchecked {
                    ++feesIndex;
                }
            }

            // Make sure nativeFee equals 0
            if (nativeFee > 0) return false;
        }

        // No overcharging
        for (uint256 feesIndex = 0; feesIndex < feesLength; ) {
            if (fees[feesIndex].amount > 0) return false;

            unchecked {
                ++feesIndex;
            }
        }

        return true;
    }

    /// @notice Set fee calculator contracts
    function setFeeCalculators(
        bytes4[] calldata selectors,
        address[] calldata tos,
        address[] calldata feeCalculators_
    ) external onlyOwner {
        uint256 length = selectors.length;
        if (length != tos.length) revert LengthMismatch();
        if (length != feeCalculators_.length) revert LengthMismatch();

        for (uint256 i = 0; i < length; ) {
            bytes4 selector = selectors[i];
            address to = tos[i];
            address feeCalculator = feeCalculators_[i];
            setFeeCalculator(selector, to, feeCalculator);
            unchecked {
                ++i;
            }
        }
    }

    function setFeeCalculator(bytes4 selector, address to, address feeCalculator) public onlyOwner {
        feeCalculators[selector][to] = feeCalculator;
        emit FeeCalculatorSet(selector, to, feeCalculator);
    }

    function getFeeCalculator(bytes4 selector, address to) public view returns (address feeCalculator) {
        feeCalculator = feeCalculators[selector][to];
        if (feeCalculator == address(0)) {
            feeCalculator = feeCalculators[selector][_DUMMY_TO_ADDRESS];
        }
    }

    function getNativeFeeCalculator() internal view returns (IFeeCalculator) {
        address nativeFeeCalculator = feeCalculators[_NATIVE_FEE_SELECTOR][_DUMMY_TO_ADDRESS];
        return IFeeCalculator(nativeFeeCalculator);
    }
}
