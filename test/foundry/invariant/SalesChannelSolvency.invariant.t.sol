// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SalesChannel} from "../../../contracts/SalesChannel.sol";
import {GreatLottoCoin} from "../../../contracts/GreatLottoCoin.sol";
import {ICoinBase} from "../../../contracts/interfaces/ICoinBase.sol";
import {AccessControlPartnerContract} from "../../../contracts/base/AccessControlPartnerContract.sol";
import {MockERC20Permit} from "../mocks/MockERC20.sol";

/// @dev 充当 PARTNER 的合约 stub（继承 AccessControlPartnerContract 以过 _isContract 1000 字节门槛）。
contract Crediter is AccessControlPartnerContract {
    constructor() AccessControlPartnerContract(address(this)) {}

    function payAndCredit(SalesChannel ch, ICoinBase coin, uint256 chnId, uint256 amount) external {
        coin.transfer(address(ch), amount); // 先转账
        ch.creditChannel(chnId, amount); // 后记账（等额）
    }
}

/// @dev 随机驱动 credit / withdraw，遵守「先 transfer 后 credit、等额」前置条件。
contract SalesChannelHandler is Test {
    SalesChannel internal ch;
    GreatLottoCoin internal glc;
    Crediter internal crediter;
    address[3] public channels; // chnId 1..3
    uint256 public creditCalls;

    constructor(SalesChannel ch_, GreatLottoCoin glc_, Crediter crediter_, address[3] memory channels_) {
        ch = ch_;
        glc = glc_;
        crediter = crediter_;
        channels = channels_;
    }

    function credit(uint256 ci, uint256 amt) external {
        uint256 chnId = (ci % 3) + 1;
        amt = bound(amt, 0, 1e24);
        deal(address(glc), address(crediter), amt);
        crediter.payAndCredit(ch, ICoinBase(address(glc)), chnId, amt);
        creditCalls++;
    }

    function withdraw(uint256 ci) external {
        address chn = channels[ci % 3];
        vm.prank(chn);
        try ch.withdraw() {} catch {}
    }

    function sumAccrued() external view returns (uint256 s) {
        for (uint256 i = 1; i <= 3; i++) s += ch.accruedOf(i);
    }

    function sumWithdrawn() external view returns (uint256 s) {
        for (uint256 i = 1; i <= 3; i++) s += ch.withdrawnOf(i);
    }
}

/// @title SalesChannelSolvencyInvariant
/// @notice 不变量：
///   - 偿付能力：balanceOf(SalesChannel) >= totalAccrued - totalWithdrawn
///   - 聚合恒等：totalAccrued == Σ accruedOf、totalWithdrawn == Σ withdrawnOf
contract SalesChannelSolvencyInvariant is StdInvariant, Test {
    SalesChannel internal ch;
    GreatLottoCoin internal glc;
    SalesChannelHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        MockERC20Permit usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);
        glc = new GreatLottoCoin(toks, owner);

        ch = new SalesChannel(address(glc), owner);
        Crediter crediter = new Crediter();
        vm.prank(owner);
        ch.grantRole(keccak256("PARTNER_CONTRACT_ROLE"), address(crediter));

        // 注册 3 个渠道（chnId 1..3）
        address[3] memory channels = [makeAddr("ch1"), makeAddr("ch2"), makeAddr("ch3")];
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(channels[i]);
            ch.registerChannel("c", block.timestamp + 1 hours);
        }

        handler = new SalesChannelHandler(ch, glc, crediter, channels);
        targetContract(address(handler));
    }

    function invariant_solvency() public view {
        assertGe(glc.balanceOf(address(ch)), ch.totalAccrued() - ch.totalWithdrawn());
    }

    function invariant_aggregateAccruedIdentity() public view {
        assertEq(ch.totalAccrued(), handler.sumAccrued());
    }

    function invariant_aggregateWithdrawnIdentity() public view {
        assertEq(ch.totalWithdrawn(), handler.sumWithdrawn());
    }
}
