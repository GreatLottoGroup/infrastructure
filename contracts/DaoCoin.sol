// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';

import "./interfaces/IDaoCoin.sol";

import "./base/BeneficiaryBase.sol";
import "./base/AccessControlPartnerContract.sol";

//import "hardhat/console.sol";

// 治理币合约，用于投票、分红等，购买彩票也会赠予一定数量的治理币
// 遵循 ERC20Votes 规范
contract DaoCoin is ERC20Votes, ERC20Permit, BeneficiaryBase, AccessControlPartnerContract, IDaoCoin{

    // 1$ -> 1 GLDC 每注1个份额
    uint256 public coinPrice = 1 * (10 ** 18);

    constructor(address _owner) ERC20Permit('GreatLottoDAOCoin') ERC20('GreatLottoDAOCoin', 'GLDC') AccessControlPartnerContract(_owner) {
    }

    // 管理员增发
    function mint(address account, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool){
        _mint(account, amount);
        return true;
    }

    // 奖池增发
    function mintToUser(address account, uint256 assets) public onlyRole(PARTNER_CONTRACT_ROLE) {
        uint256 shares = assets * 10 ** decimals() / coinPrice;
        _mint(account, shares);
    }

    // 修改价格
    function changePrice(uint256 price) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool){
        if(price == 0){
            revert ErrorInvalidAmount(0);
        }
        coinPrice = price;
        emit PriceChanged(price);
        return true;
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(BeneficiaryBase, ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

}
