// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {PermitHelper} from "./base/PermitHelper.sol";
import {SelfPermit} from "../../contracts/base/SelfPermit.sol";
import {MockERC20Permit} from "./mocks/MockERC20.sol";

/// @dev 具体化抽象 SelfPermit。
contract SelfPermitHarness is SelfPermit {}

/// @title SelfPermitTest
/// @notice 覆盖 selfPermit / selfPermitIfNecessary：成功授权、nonce 自增、过期与错签 revert，
///         以及 ifNecessary 在 allowance 充足时短路（即使签名无效也不 revert）。
contract SelfPermitTest is PermitHelper {
    SelfPermitHarness internal harness;
    MockERC20Permit internal token;

    address internal permitOwner;
    uint256 internal permitOwnerPk;

    uint256 internal constant VALUE = 1_000e18;

    function setUp() public {
        harness = new SelfPermitHarness();
        token = new MockERC20Permit("USDC", "USDC", 6);
        (permitOwner, permitOwnerPk) = makeAddrAndKey("permitOwner");
    }

    function _sign(uint256 value, uint256 deadline) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return signPermit(
            address(token), permitOwnerPk, permitOwner, address(harness), value, token.nonces(permitOwner), deadline
        );
    }

    function test_selfPermit_setsAllowanceAndBumpsNonce() public {
        uint256 dl = futureDeadline();
        (uint8 v, bytes32 r, bytes32 s) = _sign(VALUE, dl);

        harness.selfPermit(permitOwner, address(token), VALUE, dl, v, r, s);

        assertEq(token.allowance(permitOwner, address(harness)), VALUE);
        assertEq(token.nonces(permitOwner), 1);
    }

    function test_selfPermit_revert_whenExpired() public {
        uint256 expired = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _sign(VALUE, expired);
        vm.expectRevert(abi.encodeWithSignature("ERC2612ExpiredSignature(uint256)", expired));
        harness.selfPermit(permitOwner, address(token), VALUE, expired, v, r, s);
    }

    function test_selfPermit_revert_whenBadSignature() public {
        uint256 dl = futureDeadline();
        // 用错误的私钥签名 → ecrecover 恢复出 attacker 地址 != owner → ERC2612InvalidSigner(attacker, owner)
        (address attackerAddr, uint256 wrongPk) = makeAddrAndKey("attacker");
        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            address(token), wrongPk, permitOwner, address(harness), VALUE, token.nonces(permitOwner), dl
        );
        vm.expectRevert(abi.encodeWithSignature("ERC2612InvalidSigner(address,address)", attackerAddr, permitOwner));
        harness.selfPermit(permitOwner, address(token), VALUE, dl, v, r, s);
    }

    function test_selfPermitIfNecessary_permitsWhenAllowanceInsufficient() public {
        uint256 dl = futureDeadline();
        (uint8 v, bytes32 r, bytes32 s) = _sign(VALUE, dl);

        harness.selfPermitIfNecessary(permitOwner, address(token), VALUE, dl, v, r, s);
        assertEq(token.allowance(permitOwner, address(harness)), VALUE);
    }

    function test_selfPermitIfNecessary_shortCircuitsWhenAllowanceSufficient() public {
        // 先用真实 permit 把 allowance 顶到 VALUE
        uint256 dl = futureDeadline();
        (uint8 v, bytes32 r, bytes32 s) = _sign(VALUE, dl);
        harness.selfPermit(permitOwner, address(token), VALUE, dl, v, r, s);
        assertEq(token.nonces(permitOwner), 1);

        // 再次 ifNecessary：allowance 已够 → 短路，不消费签名（传垃圾签名也不 revert）
        harness.selfPermitIfNecessary(
            permitOwner, address(token), VALUE, dl, 27, bytes32(uint256(1)), bytes32(uint256(2))
        );
        // nonce 未变化 → 证明未走 permit
        assertEq(token.nonces(permitOwner), 1);
    }
}
