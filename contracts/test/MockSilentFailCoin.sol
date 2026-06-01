// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

// Hardhat-only mock: ERC20-compatible surface where transfer returns true but never moves balances.
// Used to exercise PrizePoolBase._transferTo silent-fail revert path.

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockSilentFailCoin is IERC20 {
    string public name = "MockSilentFail";
    string public symbol = "MSF";
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function mintFor(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // 故意：返回 true 但不修改任何 balance（silent-fail）
    function transfer(address to, uint256 amount) external returns (bool) {
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        emit Transfer(from, to, amount);
        return true;
    }
}
