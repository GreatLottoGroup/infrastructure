// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import "../interfaces/IBeneficiaryBase.sol";


abstract contract BeneficiaryBase is ERC20, IBeneficiaryBase {

    // 参与分润最小份额 1w
    uint256 public immutable MIN_BENEFIT_SHARES = (10 ** 4) * (10 ** 18);

    // 参与分润的人员列表
    address[] private _beneficiaryList;

    // 受益人状态
    mapping(address account => bool status) private _beneficiaryAccounts;

    // 获取受益人列表
    function getBeneficiaryList() public view returns (address[] memory){
        return _beneficiaryList;
    }

    // 是否符合分润条件
    function isBenefitAccount(address account) public view returns (bool){
        return balanceOf(account) >= MIN_BENEFIT_SHARES;
    }

    // 获取分润金额
    function getBenefitAmount(address account, uint256 totalAmount) public view returns (uint){
        uint balance = balanceOf(account);
        uint _totalSupply = totalSupply();
        if(balance >= MIN_BENEFIT_SHARES && _totalSupply > 0){
            return balance * totalAmount / _totalSupply;
        }else{
            return 0;
        }
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        super._update(from, to, amount);

        if(from != address(0)){
            if(balanceOf(from) < MIN_BENEFIT_SHARES){
                _removeFromBeneficiaryList(from);
            }else{
                _addToBeneficiaryList(from);
            }
        }

        if(to != address(0)){
            if(balanceOf(to) < MIN_BENEFIT_SHARES){
                _removeFromBeneficiaryList(to);
            }else{
                _addToBeneficiaryList(to);
            }
        }
        
    }
    // 加入分润账户列表
    function _addToBeneficiaryList(address account) private {
        if(!_beneficiaryAccounts[account]){
            _beneficiaryAccounts[account] = true;
            _beneficiaryList.push(account);
        }
    }

    // 从分润账户列表中移出
    function _removeFromBeneficiaryList(address account) private {
        if(_beneficiaryAccounts[account]){
            _beneficiaryAccounts[account] = false;           
            for(uint i = 0; i < _beneficiaryList.length; i++){
                if(_beneficiaryList[i] == account){
                    _beneficiaryList[i] = _beneficiaryList[_beneficiaryList.length - 1];
                    _beneficiaryList.pop();
                    break;
                }
            }
        }
    }
    
}
