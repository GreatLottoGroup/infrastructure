// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";


interface ICoinBase is IERC20, IERC20Permit {
    /**
     * @dev GreatLottoCoin: No need to recover
     */
    error GreatLottoCoinBaseNoNeedRecover(uint totalBalance, uint totalSupply);

    // 提款成功事件
    event GreatLottoCoinBaseWithdrawn(address indexed recipient, address indexed token, uint256 amount);
    // recover 成功事件
    event GreatLottoCoinBaseRecovered(uint256 value, uint256 totalSupply);


    // 只有奖池合约才能调用
    function mint(address token, uint256 amount, address payer) external returns (bool);
    function mint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool);
    
    function withdraw(address token, uint256 amount) external returns (bool);

    function version() external view returns (string memory);

    function checkToken(address token) external view returns (bool result);
    
    function getAmount(uint amount) external view returns (uint);

    // only owner
    function recover() external returns (uint256 value);

}
