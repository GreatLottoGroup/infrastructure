// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import "./interfaces/IGreatLottoEth.sol";

import "./base/SelfPermit.sol";
import "./base/AccessControlPartnerContract.sol";
import "./base/NoDelegateCall.sol";

//import "hardhat/console.sol";

// 奖池币
contract GreatLottoEth is ERC20Permit, SelfPermit, AccessControlPartnerContract, NoDelegateCall, IGreatLottoEth{

    // Mainnet & Local             WETH
    address[] internal _tokens = [ 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 ];

    // Sepolia                       WETH
    //address[] internal _tokens = [ 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 ];

    using SafeERC20 for IERC20;

    constructor(address _owner) ERC20Permit("GreatLottoEth") ERC20("GreatLottoEth", "GLETH") AccessControlPartnerContract(_owner){ }

    // 需要校验只有主合约才能调用
    function mint(address token, uint256 amount, address payer) external virtual noDelegateCall onlyRole(PARTNER_CONTRACT_ROLE) returns (bool){
        _depositFor(token, amount, payer, _msgSender());
        return true;
    }
    
    // 签名铸造
    function mint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external noDelegateCall onlyRole(PARTNER_CONTRACT_ROLE) returns (bool){
        selfPermitIfNecessary(payer, token, amount, deadline, v, r, s);
        _depositFor(token, amount, payer, _msgSender());
        return true;
    }

    function _depositFor(address token, uint256 amount, address payer, address recipient) private {
        // 检查token是否支持
        if(!checkToken(token)){
            revert ErrorUnsupportedToken(token);
        }

        IERC20 tokenCoin = IERC20(token);

        uint balanceBefore = tokenCoin.balanceOf(address(this));

        // 转账 form payer to thisCoin
        tokenCoin.safeTransferFrom(payer, address(this), amount);

        // 铸造 to recipient
        _mint(recipient, amount);

        // 验证是否已收到款项
        if(balanceBefore + amount > tokenCoin.balanceOf(address(this))){
            revert ErrorPaymentUnsuccessful();
        }

    }

    function wrap() public noDelegateCall payable returns (bool) {
        
        if(msg.value == 0){
            revert ErrorInvalidAmount(msg.value);
        }

        _mint(_msgSender(), msg.value);

        emit GreatLottoEthWrapped(_msgSender(), msg.value);

        return true;
    }
    
    function unwrap(uint256 amount) public noDelegateCall payable returns (bool) {

        address payable recipient = payable(_msgSender());

        if(address(this).balance < amount){
            revert ErrorInsufficientBalanceEth(address(this), address(this).balance, amount);
        }

        _burn(recipient, amount);

        bool result = recipient.send(amount);

        if(!result){
            revert ErrorPaymentUnsuccessful();
        }

        emit GreatLottoEthUnwrapped(recipient, amount);

        return true;
    }

    /**
     * @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
     */
    function withdraw(address token, uint256 amount) public noDelegateCall returns (bool) {

        // 检查token是否支持
        if(!checkToken(token)){
            revert ErrorUnsupportedToken(token);
        }

        address recipient = _msgSender();

        IERC20 tokenCoin = IERC20(token);

        uint balanceBefore = tokenCoin.balanceOf(address(this));

        if(balanceBefore < amount){
            revert ErrorInsufficientBalance(token, address(this), balanceBefore, amount);
        }

        // 销毁 form sender
        _burn(recipient, amount);

        // 提款 form thisCoin to recipient
        tokenCoin.safeTransfer(recipient, amount);

        // 验证是否已支出款项
        if(balanceBefore - amount < tokenCoin.balanceOf(address(this))){
            revert ErrorPaymentUnsuccessful();
        }

        emit GreatLottoCoinBaseWithdrawn(recipient, token, amount);

        return true;
    }

    /**
     * @dev Mint wrapped token to cover any underlyingTokens that would have been transferred by mistake. Internal
     * function that can be exposed with access control if desired.
     */
    // 只限owner调用
    function recover() public noDelegateCall onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 value) {
 
        uint256 totalBalance = address(this).balance;
        uint256 _totalSupply = totalSupply();

        for(uint8 i = 0; i < _tokens.length; i++){
            totalBalance += IERC20(_tokens[i]).balanceOf(address(this));
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

    function checkToken(address token) public view returns (bool result){
        result = false;
        for(uint8 i; i < _tokens.length; i++){
            if(_tokens[i] == token){
                result = true;
                break;
            }
        }
    } 

    function getAmount(uint amount) public view returns (uint) {
        return amount * 10 ** decimals();
    }

    /**
     * @inheritdoc IERC20Permit
     */
    function nonces(address owner) public view virtual override(ERC20Permit, IERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    function version() public view returns (string memory) {
        return _EIP712Version();
    }


}
