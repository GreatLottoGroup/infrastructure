// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {ERC721Permit} from "../../../contracts/base/ERC721Permit.sol";

/// @dev 具体化抽象 ERC721Permit：提供最小 per-tokenId nonce 存储 + public mint，
///      供 permit 基类单测使用（对齐 SelfPermitHarness / MockEntropyConsumer 的 harness 约定）。
contract ERC721PermitHarness is ERC721Permit {
    // tokenId → 下一枚 permit nonce（nonce 存储由子类负责，见 ERC721Permit 的两个虚函数）
    mapping(uint256 => uint256) private _nonces;

    constructor() ERC721Permit("ERC721PermitHarness", "EPH") {}

    /// @dev 取当前 nonce 并自增（每次成功 permit 消费一枚）
    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _nonces[tokenId]++;
    }

    function _getNonce(uint256 tokenId) internal view override returns (uint256) {
        return _nonces[tokenId];
    }

    /// @dev 测试入口：直接铸造，绕过任何业务权限
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
