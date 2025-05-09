// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import '@openzeppelin/contracts/access/AccessControl.sol';
import "../interfaces/IErrors.sol";

abstract contract AccessControlPartnerContract is AccessControl, IErrors{

    bytes32 public constant PARTNER_CONTRACT_ROLE = keccak256("PARTNER_CONTRACT_ROLE");

    constructor(address _owner){

        _grantRole(DEFAULT_ADMIN_ROLE, _owner == address(0) ? _msgSender() : _owner);
        
        _setRoleAdmin(PARTNER_CONTRACT_ROLE, DEFAULT_ADMIN_ROLE);

    }

    /**
     * @inheritdoc AccessControl
     */    
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        // 判断地址必须为合约地址
        if(account == address(0)){
            revert ErrorZeroAddress();
        }else if(account.code.length == 0){
            revert ErrorInvalidAddress(account);
        }

        super.grantRole(role, account);
    }

}
