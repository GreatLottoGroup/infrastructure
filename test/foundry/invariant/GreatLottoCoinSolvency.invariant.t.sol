// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {GreatLottoCoin} from "../../../contracts/GreatLottoCoin.sol";
import {MockERC20Permit} from "../mocks/MockERC20.sol";

/// @dev 随机驱动 mint / withdraw / 误转入，供 invariant 校验偿付能力。
contract GreatLottoCoinHandler is Test {
    GreatLottoCoin internal glc;
    MockERC20Permit internal usdc;

    constructor(GreatLottoCoin glc_, MockERC20Permit usdc_) {
        glc = glc_;
        usdc = usdc_;
    }

    function mintFlow(uint256 amount) external {
        amount = bound(amount, 1, 1e9);
        usdc.mint(address(this), amount * 1e6);
        usdc.approve(address(glc), amount * 1e6);
        glc.mint(address(usdc), amount, address(this)); // GLC 铸给 handler
    }

    function withdrawFlow(uint256 amount) external {
        amount = bound(amount, 1, 1e9);
        if (glc.balanceOf(address(this)) < amount * 1e18) return;
        glc.withdraw(address(usdc), amount);
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 0, 1e9);
        usdc.mint(address(glc), amount * 1e6); // 仅增加背书、不铸 GLC
    }
}

/// @title GreatLottoCoinSolvencyInvariant
/// @notice 不变量：GLC 总供给（18 位）<= 合约持有底层稳定币的等值背书（balance × 10^(18-6)）。
///         即每一枚 GLC 都有底层资产兜底，永不超发。
contract GreatLottoCoinSolvencyInvariant is StdInvariant, Test {
    GreatLottoCoin internal glc;
    MockERC20Permit internal usdc;
    GreatLottoCoinHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);
        glc = new GreatLottoCoin(toks, owner);

        handler = new GreatLottoCoinHandler(glc, usdc);
        vm.prank(owner);
        glc.grantRole(keccak256("PARTNER_CONTRACT_ROLE"), address(handler));
        targetContract(address(handler));
    }

    function invariant_supplyBackedByUnderlying() public view {
        // 底层 6 位 → 18 位等值：balance × 10^12
        assertLe(glc.totalSupply(), usdc.balanceOf(address(glc)) * 1e12);
    }
}
