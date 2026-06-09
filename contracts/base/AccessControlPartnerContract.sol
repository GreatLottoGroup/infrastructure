// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import '@openzeppelin/contracts/access/AccessControl.sol';
import "../interfaces/IErrorsBase.sol";

import "hardhat/console.sol";

abstract contract AccessControlPartnerContract is AccessControl, IErrorsBase{

    bytes32 public constant PARTNER_CONTRACT_ROLE = keccak256("PARTNER_CONTRACT_ROLE");

    constructor(address owner_){

        _grantRole(DEFAULT_ADMIN_ROLE, owner_ == address(0) ? _msgSender() : owner_);
        
        _setRoleAdmin(PARTNER_CONTRACT_ROLE, DEFAULT_ADMIN_ROLE);

    }

    function _isContract(address addr) internal view returns (bool) {
        uint size = addr.code.length;
        return size > 1000;
    }

    /**
     * @inheritdoc AccessControl
     */    
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        // 判断地址必须为合约地址
        if(account == address(0)){
            revert ErrorZeroAddress();
        }else if(!_isContract(account)){
            revert ErrorInvalidAddress(account);
        }

        super.grantRole(role, account);
    }

}
