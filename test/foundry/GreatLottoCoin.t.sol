// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {PermitHelper} from "./base/PermitHelper.sol";
import {GreatLottoCoin} from "../../contracts/GreatLottoCoin.sol";
import {IGreatLottoCoin} from "../../contracts/interfaces/IGreatLottoCoin.sol";
import {ICoinBase} from "../../contracts/interfaces/ICoinBase.sol";
import {IErrorsBase} from "../../contracts/interfaces/IErrorsBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockERC20Permit} from "./mocks/MockERC20.sol";
import {MockSilentFailCoin} from "./mocks/MockSilentFailCoin.sol";

/// @title GreatLottoCoinTest
/// @notice GreatLottoCoin（GLC = 白名单稳定币的 18 位封装）全覆盖：直接 mint / permit mint /
///         withdraw / recover / checkToken / getAmount / nonces / version，含权限与异常分支。
///         **完全本地化**：底层稳定币用 6 位 MockERC20Permit，免 Arbitrum fork。
contract GreatLottoCoinTest is PermitHelper {
    GreatLottoCoin internal glc;
    MockERC20Permit internal usdc; // 6 位精度，支持 permit

    bytes32 internal constant PARTNER_ROLE = keccak256("PARTNER_CONTRACT_ROLE");
    bytes32 internal constant ADMIN_ROLE = 0x00;

    function setUp() public {
        usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);
        glc = new GreatLottoCoin(toks, owner);
        // 测试合约充当 PARTNER（合约身份），可调 mint
        vm.prank(owner);
        glc.grantRole(PARTNER_ROLE, address(this));
    }

    // ---------------------------------------------------------------------
    // 元数据 / 视图
    // ---------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(glc.name(), "GreatLottoCoin");
        assertEq(glc.symbol(), "GLC");
        assertEq(glc.decimals(), 18);
        assertEq(glc.version(), "1");
    }

    function test_checkToken() public {
        assertTrue(glc.checkToken(address(usdc)));
        assertFalse(glc.checkToken(makeAddr("other")));
    }

    function test_getAmount_scalesTo18() public view {
        assertEq(glc.getAmount(100), 100e18);
    }

    function test_nonces_startAtZero() public view {
        assertEq(glc.nonces(alice), 0);
    }

    // ---------------------------------------------------------------------
    // mint (直接)
    // ---------------------------------------------------------------------

    function test_mint_direct_pullsUnderlyingAndMintsGlc() public {
        usdc.mint(alice, 100e6);
        vm.prank(alice);
        usdc.approve(address(glc), 100e6);

        bool ok = glc.mint(address(usdc), 100, alice); // 调用者（本合约）= 收 GLC 方
        assertTrue(ok);

        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(address(glc)), 100e6);
        assertEq(glc.balanceOf(address(this)), 100e18);
    }

    function test_mint_revert_whenUnsupportedToken() public {
        address other = makeAddr("other");
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorUnsupportedToken.selector, other));
        glc.mint(other, 100, alice);
    }

    function test_mint_revert_whenNotPartner() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, PARTNER_ROLE)
        );
        glc.mint(address(usdc), 100, alice);
    }

    // ---------------------------------------------------------------------
    // mint (permit)
    // ---------------------------------------------------------------------

    function test_mint_withPermit() public {
        (address payer, uint256 pk) = makeAddrAndKey("payer");
        usdc.mint(payer, 100e6);
        uint256 dl = futureDeadline();
        // permit: payer 授权 glc 花 100e6 底层币
        (uint8 v, bytes32 r, bytes32 s) =
            signPermit(address(usdc), pk, payer, address(glc), 100e6, usdc.nonces(payer), dl);

        bool ok = glc.mint(address(usdc), 100, payer, dl, v, r, s);
        assertTrue(ok);
        assertEq(usdc.balanceOf(address(glc)), 100e6);
        assertEq(glc.balanceOf(address(this)), 100e18);
    }

    // ---------------------------------------------------------------------
    // withdraw
    // ---------------------------------------------------------------------

    function test_withdraw_burnsGlcAndReturnsUnderlying() public {
        // 先 mint 让本合约持 100 GLC、glc 持 100e6 usdc
        usdc.mint(address(this), 100e6);
        usdc.approve(address(glc), 100e6);
        glc.mint(address(usdc), 100, address(this));

        bool ok = glc.withdraw(address(usdc), 40);
        assertTrue(ok);
        assertEq(glc.balanceOf(address(this)), 60e18);
        assertEq(usdc.balanceOf(address(this)), 40e6);
        assertEq(usdc.balanceOf(address(glc)), 60e6);
    }

    function test_withdraw_revert_whenUnsupportedToken() public {
        address other = makeAddr("other");
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorUnsupportedToken.selector, other));
        glc.withdraw(other, 1);
    }

    function test_withdraw_revert_whenInsufficientUnderlying() public {
        // 给 alice 凭空塞 GLC（deal）但 glc 不持任何 usdc → 提款时底层不足
        deal(address(glc), alice, 300e18);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IErrorsBase.ErrorInsufficientBalance.selector, address(usdc), address(glc), 0, 300e6)
        );
        glc.withdraw(address(usdc), 300);
    }

    // ---------------------------------------------------------------------
    // recover
    // ---------------------------------------------------------------------

    function test_recover_mintsExcessToOwner() public {
        // 直接把 usdc 误转进 glc（不铸 GLC）→ 底层价值 100e18 > 供给 0
        usdc.mint(address(glc), 100e6);

        vm.expectEmit(false, false, false, true, address(glc));
        emit ICoinBase.GreatLottoCoinBaseRecovered(100e18, 100e18);
        vm.prank(owner);
        uint256 value = glc.recover();

        assertEq(value, 100e18);
        assertEq(glc.balanceOf(owner), 100e18);
    }

    function test_recover_revert_whenNoNeed() public {
        // 正常 mint 后 底层价值 == 供给 → 无需 recover
        usdc.mint(address(this), 100e6);
        usdc.approve(address(glc), 100e6);
        glc.mint(address(usdc), 100, address(this));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ICoinBase.GreatLottoCoinBaseNoNeedRecover.selector, 100e18, 100e18));
        glc.recover();
    }

    function test_recover_revert_whenNotAdmin() public {
        usdc.mint(address(glc), 100e6);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        glc.recover();
    }

    // ---------------------------------------------------------------------
    // 异常代币：收/付后置余额校验（ErrorPaymentUnsuccessful）
    // ---------------------------------------------------------------------

    /// @dev 用 silent-fail 底层币（transfer 返 true 但不动余额）触发 mint/_depositFor 的收款后置校验。
    function _glcWithSilentFail() internal returns (GreatLottoCoin g, MockSilentFailCoin sf) {
        sf = new MockSilentFailCoin();
        address[] memory toks = new address[](1);
        toks[0] = address(sf);
        g = new GreatLottoCoin(toks, owner);
        vm.prank(owner);
        g.grantRole(PARTNER_ROLE, address(this));
    }

    function test_mint_revert_whenPaymentUnsuccessful() public {
        (GreatLottoCoin g, MockSilentFailCoin sf) = _glcWithSilentFail();
        // safeTransferFrom 返回 true 但合约实际未收到 → balanceBefore+underlying > balanceOf → revert
        vm.expectRevert(IErrorsBase.ErrorPaymentUnsuccessful.selector);
        g.mint(address(sf), 100, alice);
    }

    function test_withdraw_revert_whenPaymentUnsuccessful() public {
        (GreatLottoCoin g, MockSilentFailCoin sf) = _glcWithSilentFail();
        // 让合约「账面」持有底层币、并给 alice 凭空塞 GLC 以通过销毁
        sf.mintFor(address(g), 100e18);
        deal(address(g), alice, 100e18);
        // safeTransfer 返回 true 但未支出 → balanceBefore-payAmount < balanceOf → revert
        vm.prank(alice);
        vm.expectRevert(IErrorsBase.ErrorPaymentUnsuccessful.selector);
        g.withdraw(address(sf), 100);
    }
}
