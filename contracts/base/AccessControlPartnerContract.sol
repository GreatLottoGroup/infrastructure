// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import '@openzeppelin/contracts/access/AccessControl.sol';
import "../interfaces/IErrorsBase.sol";

/// @title AccessControlPartnerContract
/// @notice OpenZeppelin AccessControl extended with a `PARTNER_CONTRACT_ROLE` that may only be granted to audited
///         contracts (never EOAs), used to gate cross-contract entry points.
/// @dev    `grantRole` is overridden to reject the zero address for any role, and to require that any account
///         granted `PARTNER_CONTRACT_ROLE` is a contract (code size > 1000). Other roles (including
///         `DEFAULT_ADMIN_ROLE`) may still be granted to EOAs / multisigs, matching native OZ behavior.
abstract contract AccessControlPartnerContract is AccessControl, IErrorsBase{

    /// @notice Role granted only to audited partner contracts (never EOAs) to authorize cross-contract calls.
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
        // Zero-address guard: no role may be granted to address(0).
        if(account == address(0)){
            revert ErrorZeroAddress();
        }
        // Contract-address guard applies only to PARTNER_CONTRACT_ROLE: a partner must be an audited contract,
        // never an EOA. Other roles (including DEFAULT_ADMIN_ROLE) are exempt and may be granted to EOAs /
        // multisigs, consistent with native OZ AccessControl, to support post-deploy admin transfer / addition.
        if(role == PARTNER_CONTRACT_ROLE && !_isContract(account)){
            revert ErrorInvalidAddress(account);
        }

        super.grantRole(role, account);
    }

}
