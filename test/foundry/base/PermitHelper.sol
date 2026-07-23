// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {BaseTest} from "./BaseTest.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @dev EIP-2612 permit 签名脚手架（vm.sign）。需要 permit 的测试继承本基类。
abstract contract PermitHelper is BaseTest {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function signPermit(
        address token,
        uint256 ownerPk,
        address ownerAddr,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, ownerAddr, spender, value, nonce, deadline));
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(ownerPk, digest);
    }
}
