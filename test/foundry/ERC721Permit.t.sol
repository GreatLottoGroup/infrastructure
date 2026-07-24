// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {PermitHelper} from "./base/PermitHelper.sol";
import {ERC721Permit} from "../../contracts/base/ERC721Permit.sol";
import {ERC721PermitHarness} from "./harness/ERC721PermitHarness.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";

/// @title ERC721PermitTest
/// @notice 覆盖 ERC721Permit 抽象基类的 permit 行为：happy（approve + nonce++）、过期、错签、
///         自己 permit 自己（NoNeedApprove）、ERC1271 合约钱包有效/拒签、version 与 PERMIT_TYPEHASH 不变量。
/// @dev    代码随 Uniswap 衍生文件从 GreatLottoCore 迁入 infra 后，基类边界测试跟随归位到基类之家；
///         下游 GreatLottoNFT.t.sol 仅保留一条 permit 接线冒烟（集成断言）。
contract ERC721PermitTest is PermitHelper {
    ERC721PermitHarness internal token;

    uint256 internal constant TOKEN_ID = 1;

    function setUp() public {
        token = new ERC721PermitHarness();
    }

    /// happy path：EOA 持有人签名 → permit 授权 spender + nonce 自增
    function testPermitHappy() public {
        (address permitOwner, uint256 pk) = makeAddrAndKey("permitOwner");
        token.mint(permitOwner, TOKEN_ID);
        uint256 deadline = futureDeadline();
        uint256 nonce = token.nonces(TOKEN_ID);

        (uint8 v, bytes32 r, bytes32 s) = signERC721Permit(address(token), pk, bob, TOKEN_ID, nonce, deadline);

        token.permit(bob, TOKEN_ID, deadline, v, r, s);
        assertEq(token.getApproved(TOKEN_ID), bob, "approved");
        assertEq(token.nonces(TOKEN_ID), nonce + 1, "nonce++");
    }

    /// deadline 已过 → ERC2612ExpiredSignature
    function testPermitExpiredReverts() public {
        (address permitOwner, uint256 pk) = makeAddrAndKey("permitOwner");
        token.mint(permitOwner, TOKEN_ID);
        uint256 deadline = block.timestamp - 1; // BaseTest 已 warp 到非零基准，不会下溢
        (uint8 v, bytes32 r, bytes32 s) =
            signERC721Permit(address(token), pk, bob, TOKEN_ID, token.nonces(TOKEN_ID), deadline);
        vm.expectRevert(abi.encodeWithSelector(ERC721Permit.ERC2612ExpiredSignature.selector, deadline));
        token.permit(bob, TOKEN_ID, deadline, v, r, s);
    }

    /// 错误私钥签名 → ecrecover 出 attacker ≠ owner → ERC2612InvalidSigner(recovered, owner)
    function testPermitInvalidSignerReverts() public {
        (address permitOwner,) = makeAddrAndKey("permitOwner");
        token.mint(permitOwner, TOKEN_ID);
        uint256 deadline = futureDeadline();
        (address attacker, uint256 wrongPk) = makeAddrAndKey("attacker");
        (uint8 v, bytes32 r, bytes32 s) =
            signERC721Permit(address(token), wrongPk, bob, TOKEN_ID, token.nonces(TOKEN_ID), deadline);
        vm.expectRevert(abi.encodeWithSelector(ERC721Permit.ERC2612InvalidSigner.selector, attacker, permitOwner));
        token.permit(bob, TOKEN_ID, deadline, v, r, s);
    }

    /// spender == owner → ERC721PermitNoNeedApprove
    function testPermitToOwnerReverts() public {
        (address permitOwner, uint256 pk) = makeAddrAndKey("permitOwner");
        token.mint(permitOwner, TOKEN_ID);
        uint256 deadline = futureDeadline();
        (uint8 v, bytes32 r, bytes32 s) =
            signERC721Permit(address(token), pk, permitOwner, TOKEN_ID, token.nonces(TOKEN_ID), deadline);
        vm.expectRevert(
            abi.encodeWithSelector(ERC721Permit.ERC721PermitNoNeedApprove.selector, permitOwner, permitOwner)
        );
        token.permit(permitOwner, TOKEN_ID, deadline, v, r, s);
    }

    /// 合约钱包（owner.code.length > 0）→ permit 走 ERC1271 isValidSignature 分支（接受）
    function testPermitContractWalletValid() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();
        token.mint(address(wallet), TOKEN_ID);
        uint256 deadline = futureDeadline();
        // isValidSignature 返回 magic value，任意 (v,r,s) 即被接受
        token.permit(bob, TOKEN_ID, deadline, 27, bytes32(uint256(1)), bytes32(uint256(2)));
        assertEq(token.getApproved(TOKEN_ID), bob, "approved via ERC1271");
    }

    /// 合约钱包拒签（isValidSignature != magic）→ require 'Unauthorized'
    function testPermitContractWalletInvalidReverts() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet();
        wallet.setAccept(false);
        token.mint(address(wallet), TOKEN_ID);
        uint256 deadline = futureDeadline();
        vm.expectRevert(bytes("Unauthorized"));
        token.permit(bob, TOKEN_ID, deadline, 27, bytes32(uint256(1)), bytes32(uint256(2)));
    }

    function testVersion() public view {
        assertEq(token.version(), "1", "version");
    }

    /// 防回归：PERMIT_TYPEHASH 常量必须与 EIP-712 规范串一致（改坏它会静默令所有历史签名失效）
    function testPermitTypehashMatchesSpec() public view {
        assertEq(
            token.PERMIT_TYPEHASH(),
            keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)"),
            "PERMIT_TYPEHASH"
        );
    }
}
