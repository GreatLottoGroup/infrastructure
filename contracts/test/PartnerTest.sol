// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../interfaces/ICoinBase.sol";
import "../interfaces/IDaoCoin.sol";

contract PartnerTest  {

    // Dao治理币地址
    address public immutable DaoCoinAddress;
    // 资产币地址
    address public immutable GreatLottoCoinAddress;
    address public immutable GreatLottoEthAddress;

    constructor(address greatLottoCoinAddress, address greatLottoEthAddress, address daoCoinAddress) {
        DaoCoinAddress = daoCoinAddress;
        GreatLottoCoinAddress = greatLottoCoinAddress;
        GreatLottoEthAddress = greatLottoEthAddress;
    }

    // DaoCoin mintToUser
    function daoMintToUser(address account, uint256 assets, bool isEth) external returns (bool){
        IDaoCoin daoCoin = IDaoCoin(DaoCoinAddress);
        daoCoin.mintToUser(account, assets, isEth);
        return true;
    }

    // GreatLottoEth mint
    function ethCoinMint(address token, uint256 amount, address payer) external returns (bool){
        ICoinBase greatLottoEth = ICoinBase(GreatLottoEthAddress);
        greatLottoEth.mint(token, amount, payer);
        greatLottoEth.transfer(payer, amount);
        return true;
    }

    // GreatLottoEth mint promise
    function ethCoinMint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool){
        ICoinBase greatLottoEth = ICoinBase(GreatLottoEthAddress);
        greatLottoEth.mint(token, amount, payer, deadline, v, r, s);
        greatLottoEth.transfer(payer, amount);
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