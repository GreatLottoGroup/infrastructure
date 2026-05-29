// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../interfaces/ICoinBase.sol";
import "../interfaces/IDaoCoin.sol";

contract PartnerTest  {

    // Dao治理币地址
    address public immutable DaoCoinAddress;
    // 资产币地址
    address public immutable GreatLottoCoinAddress;

    constructor(address greatLottoCoinAddress, address daoCoinAddress) {
        DaoCoinAddress = daoCoinAddress;
        GreatLottoCoinAddress = greatLottoCoinAddress;
    }

    // DaoCoin mintToUser
    function daoMintToUser(address account, uint256 assets) external returns (bool){
        IDaoCoin daoCoin = IDaoCoin(DaoCoinAddress);
        daoCoin.mintToUser(account, assets);
        return true;
    }

    // GreatLottoCoin mint
    function coinMint(address token, uint256 amount, address payer) external returns (bool){
        ICoinBase greatLottoCoin = ICoinBase(GreatLottoCoinAddress);
        greatLottoCoin.mint(token, amount, payer);
        greatLottoCoin.transfer(payer, greatLottoCoin.getAmount(amount));
        return true;
    }

    // GreatLottoCoin mint promise
    function coinMint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool){
        ICoinBase greatLottoCoin = ICoinBase(GreatLottoCoinAddress);
        greatLottoCoin.mint(token, amount, payer, deadline, v, r, s);
        greatLottoCoin.transfer(payer, greatLottoCoin.getAmount(amount));
        return true;
    }

}
