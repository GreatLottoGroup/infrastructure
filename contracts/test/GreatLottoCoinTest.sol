// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../GreatLottoCoin.sol";

contract GreatLottoCoinTest is GreatLottoCoin {

    constructor(address[] memory tokensAddress_, address owner_) GreatLottoCoin(tokensAddress_, owner_) {}

    // 向给定账户无偿铸造货币 only for test
    function mintFor(address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool){
        _mint(recipient, amount);
        return true;
    } 

    // 定向销毁货币 only for test
    function burnFrom(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool){
        _burn(account, amount);
        return true;
    }

}