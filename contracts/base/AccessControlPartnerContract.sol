// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import '@openzeppelin/contracts/access/AccessControl.sol';
import "../interfaces/IErrorsBase.sol";

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
        // 零地址守卫：任何角色都不得授予 address(0)
        if(account == address(0)){
            revert ErrorZeroAddress();
        }
        // 合约地址守卫仅对 PARTNER_CONTRACT_ROLE 生效：partner 必须是审计过的合约、绝不能是 EOA。
        // 其它角色（含 DEFAULT_ADMIN_ROLE）不受此限，可授予 EOA / 多签，与原生 OZ AccessControl 一致，
        // 以支持部署后转移/追加管理员。
        if(role == PARTNER_CONTRACT_ROLE && !_isContract(account)){
            revert ErrorInvalidAddress(account);
        }

        super.grantRole(role, account);
    }

}
