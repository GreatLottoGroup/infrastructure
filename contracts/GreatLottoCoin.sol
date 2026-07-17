// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import "./interfaces/IGreatLottoCoin.sol";

import "./base/SelfPermit.sol";
import "./base/NoDelegateCall.sol";
import "./base/AccessControlPartnerContract.sol";

/// @title GreatLottoCoin
/// @notice The GreatLottoCoin (GLC) prize-pool currency: an 18-decimal ERC20 wrapper minted 1:1 (in whole
///         units) against a whitelist of underlying stablecoins, with EIP-2612 permit support.
/// @dev    Implements `IGreatLottoCoin` / `ICoinBase`. Minting is gated to `PARTNER_CONTRACT_ROLE` (the prize
///         pool contract); `withdraw` burns GLC for the underlying; `recover` (owner) sweeps surplus underlying.
contract GreatLottoCoin is ERC20Permit, SelfPermit, AccessControlPartnerContract, NoDelegateCall, ReentrancyGuard, IGreatLottoCoin{

    using SafeERC20 for IERC20;

    address[] internal _tokens;

    constructor(address[] memory tokensAddress_, address owner_) 
        ERC20Permit("GreatLottoCoin") 
        ERC20("GreatLottoCoin", "GLC") 
        AccessControlPartnerContract(owner_)
    {
        _tokens = tokensAddress_;
    }

    /// @inheritdoc ICoinBase
    function mint(address token, uint256 amount, address payer) external virtual noDelegateCall onlyRole(PARTNER_CONTRACT_ROLE) returns (bool){
        _depositFor(token, amount, payer, _msgSender());
        return true;
    }

    /// @inheritdoc ICoinBase
    function mint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external noDelegateCall onlyRole(PARTNER_CONTRACT_ROLE) returns (bool){
        selfPermitIfNecessary(payer, token, getAmount(token, amount), deadline, v, r, s);
        _depositFor(token, amount, payer, _msgSender());
        return true;
    }

    function _depositFor(address token, uint256 amount, address payer, address recipient) private {
        // 检查token是否支持
        if(!checkToken(token)){
            revert ErrorUnsupportedToken(token);
        }
        IERC20 tokenCoin = IERC20(token);
        // 换算
        // 底币
        uint256 underlyingAmount = getAmount(token, amount);
        // 本币
        uint256 localAmount = getAmount(amount);

        uint balanceBefore = tokenCoin.balanceOf(address(this));

        // 转账 form payer to thisCoin
        tokenCoin.safeTransferFrom(payer, address(this), underlyingAmount);

        // 铸造 to recipient
        _mint(recipient, localAmount);

        // 验证是否已收到款项
        if(balanceBefore + underlyingAmount > tokenCoin.balanceOf(address(this))){
            revert ErrorPaymentUnsuccessful();
        }

    }

    /// @inheritdoc ICoinBase
    /// @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
    function withdraw(address token, uint256 amount) external noDelegateCall nonReentrant returns (bool) {

        address recipient = _msgSender();

        // 检查token是否支持
        if(!checkToken(token)){
            revert ErrorUnsupportedToken(token);
        }
        IERC20 tokenCoin = IERC20(token);
        // 本币
        uint256 localAmount = getAmount(amount);
        // 支付币
        uint payAmount = getAmount(token, amount);

        // 余额检测
        uint balanceBefore = tokenCoin.balanceOf(address(this));
        if(balanceBefore < payAmount){
            revert ErrorInsufficientBalance(token, address(this), balanceBefore, payAmount);
        }

        // 销毁 form sender
        _burn(recipient, localAmount);

        // 提款 form thisCoin to recipient
        tokenCoin.safeTransfer(recipient, payAmount);

        // 验证是否已支出款项
        if(balanceBefore - payAmount < tokenCoin.balanceOf(address(this))){
            revert ErrorPaymentUnsuccessful();
        }

        emit GreatLottoCoinBaseWithdrawn(recipient, token, payAmount);

        return true;
    }

    /// @inheritdoc ICoinBase
    /// @dev Mints wrapped token to cover any underlying tokens transferred in by mistake (surplus beyond
    ///      totalSupply). Owner-only (`DEFAULT_ADMIN_ROLE`).
    function recover() public noDelegateCall onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 value) {
 
        uint256 totalBalance = 0;
        uint256 _totalSupply = totalSupply();

        for(uint8 i = 0; i < _tokens.length; i++){
            totalBalance += getAmountWithDecimals(_tokens[i], IERC20(_tokens[i]).balanceOf(address(this)));
        }

        if(totalBalance <= _totalSupply){
            revert GreatLottoCoinBaseNoNeedRecover(totalBalance, _totalSupply);
        }

        value = totalBalance - _totalSupply;

        // 铸造 to Owner
        _mint(_msgSender(), value);

        // 触发事件
        emit GreatLottoCoinBaseRecovered(value, totalSupply());

    }

    /// @inheritdoc ICoinBase
    function getAmount(uint amount) public view returns (uint) {
        return amount * 10 ** decimals();
    }

    function getAmount(address token, uint amount) internal view returns (uint) {
        return amount * 10 ** IERC20Metadata(token).decimals();
    }    

    function getAmountWithDecimals(address token, uint amount) internal view returns (uint) {
        return amount * 10 ** (decimals() - IERC20Metadata(token).decimals());
    }
    
    /// @inheritdoc ICoinBase
    function checkToken(address token) public view returns (bool result){
        result = false;
        for(uint8 i; i < _tokens.length; i++){
            if(_tokens[i] == token){
                result = true;
                break;
            }
        }
    } 

    /**
     * @inheritdoc IERC20Permit
     */
    function nonces(address owner) public view virtual override(ERC20Permit, IERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc ICoinBase
    function version() public view returns (string memory) {
        return _EIP712Version();
    }

}
