// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @notice 测试用合约钱包：实现 ERC1271 isValidSignature，覆盖 ERC721Permit 的
///         `owner.code.length > 0` 分支。可持有 ERC721（实现 onERC721Received）。
/// @dev    `accept` 开关控制 isValidSignature 返回 magic value（0x1626ba7e）还是 0xffffffff，
///         以分别覆盖「合约钱包签名有效」与「无效→require 失败」两条路径。
contract MockERC1271Wallet is IERC1271, IERC721Receiver {
    bool public accept = true;

    function setAccept(bool v) external {
        accept = v;
    }

    function isValidSignature(bytes32, bytes memory) external view override returns (bytes4) {
        return accept ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
