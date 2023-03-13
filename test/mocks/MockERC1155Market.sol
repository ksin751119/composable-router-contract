// SPDX-License-Identifier: MIT

import {SafeERC20, IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {ERC1155Holder} from 'openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import {MockERC1155} from './MockERC1155.sol';

pragma solidity ^0.8.0;

contract MockERC1155Market is ERC1155Holder {
    using SafeERC20 for IERC20;

    uint256 public constant amount = 1000000;

    MockERC1155 public nft;
    IERC20 public token;

    constructor(IERC20 token_) {
        token = token_;
        nft = new MockERC1155('');
    }

    function nftToToken(uint256 tokenId, uint256 nftAmount) external {
        nft.safeTransferFrom(msg.sender, address(this), tokenId, nftAmount, '');
        token.transfer(msg.sender, nftAmount * amount);
    }

    function tokenToNft(uint256 tokenId, uint256 nftAmount) external {
        token.transferFrom(msg.sender, address(this), nftAmount * amount);
        uint256 marketBalanceOf = nft.balanceOf(address(this), tokenId);
        if (marketBalanceOf < nftAmount) {
            nft.mint(address(this), tokenId, nftAmount - marketBalanceOf);
        }
        nft.safeTransferFrom(address(this), msg.sender, tokenId, nftAmount, '');
    }

    function nftBatchToToken(uint256[] calldata tokenIds, uint256[] calldata nftAmounts) external {
        nft.safeBatchTransferFrom(msg.sender, address(this), tokenIds, nftAmounts, '');

        uint256 totalNftAmount;
        for (uint256 i; i < nftAmounts.length; i++) {
            totalNftAmount += nftAmounts[i];
        }
        token.transfer(msg.sender, totalNftAmount * amount);
    }

    function tokenToNftBatch(uint256[] calldata tokenIds, uint256[] calldata nftAmounts) external {
        uint256 totalNftAmount;
        for (uint256 i; i < nftAmounts.length; i++) {
            totalNftAmount += nftAmounts[i];

            uint256 marketBalanceOf = nft.balanceOf(address(this), tokenIds[i]);
            if (marketBalanceOf < nftAmounts[i]) {
                nft.mint(address(this), tokenIds[i], nftAmounts[i] - marketBalanceOf);
            }
        }
        token.transferFrom(msg.sender, address(this), totalNftAmount * amount);
        nft.safeBatchTransferFrom(address(this), msg.sender, tokenIds, nftAmounts, '');
    }
}
