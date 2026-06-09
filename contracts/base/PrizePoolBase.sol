// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICoinBase.sol";
import "../interfaces/IDaoCoin.sol";
import "../interfaces/ISalesChannel.sol";
import "../interfaces/IPrizePoolBase.sol";

import "./AccessControlPartnerContract.sol";
import "./NoDelegateCall.sol";

/// @title PrizePoolBase
/// @notice 抽象奖池基类：提供奖金池收款（GLC 直接转账 / 外币 mint / EIP-2612 permit）、分润计算、
///         渠道与 DAO 利润池两段分润 pipeline、治理币增发等可组合的 internal helper，以及独立的
///         渠道 / sell 分润率治理 setter。下游通过 `is PrizePoolBase` 继承并按需组合 helper。
/// @dev    helper 全部 internal；setter external，受 `DEFAULT_ADMIN_ROLE` 守护。
///         调用方负责保证 `channelBenefitRate + sellBenefitRate <= 1000`，超过会让
///         `_distributeChannelAndDaoBenefits` underflow revert（已知 governance footgun，base 不强制 cap）。
abstract contract PrizePoolBase is AccessControlPartnerContract, NoDelegateCall, IPrizePoolBase {
    using SafeERC20 for ICoinBase;

    // 资产币地址（GLC）
    address public immutable GreatLottoCoinAddress;
    // Dao 治理币地址
    address public immutable DaoCoinAddress;
    // Dao 利润池
    address public immutable DaoBenefitPoolAddress;
    // SalesChannel 注册表
    address public immutable SalesChannelAddress;

    // 渠道分润率（千分比）；public getter 实现 IPrizePoolBase.channelBenefitRate()
    uint16 public override channelBenefitRate;

    // 销售分润率（千分比）；public getter 实现 IPrizePoolBase.sellBenefitRate()
    uint16 public override sellBenefitRate;

    // 付奖兜底：push 付款（如 callback 内付奖、债务清偿）失败时按 user 记账，转 pull 模式，
    // 避免整笔交易 / entropy 回调 revert。资产币为单一 GLC，故仅记金额。
    mapping(address user => uint256) private _pendingPayouts;

    constructor(
        address coin,
        address daoCoinAddr,
        address daoBenefitPoolAddr,
        address salesChannelAddr,
        address owner_,
        uint16 initialChannelRate,
        uint16 initialSellRate
    ) 
    AccessControlPartnerContract(owner_) 
    {
        GreatLottoCoinAddress = coin;
        DaoCoinAddress = daoCoinAddr;
        DaoBenefitPoolAddress = daoBenefitPoolAddr;
        SalesChannelAddress = salesChannelAddr;
        channelBenefitRate = initialChannelRate;
        sellBenefitRate = initialSellRate;
    }

    function _getCoin() internal view returns (ICoinBase coin) {
        coin = ICoinBase(GreatLottoCoinAddress);
    }

    /// @notice 收款（直接版）
    /// @dev    GLC 路径：getAmount + safeTransferFrom；外币路径：coin.mint
    function _colletWithCoin(address token, address payer, uint amount) internal returns (ICoinBase coin) {
        if (amount == 0) {
            revert ErrorInvalidAmount(0);
        }
        coin = _getCoin();

        if (token == GreatLottoCoinAddress) {
            uint underlyingAmount = coin.getAmount(amount);
            coin.safeTransferFrom(payer, address(this), underlyingAmount);
        } else {
            coin.mint(token, amount, payer);
        }
    }

    /// @notice 收款（permit 版）
    /// @dev    GLC 路径：allowance 不足时先 permit，再 safeTransferFrom；外币路径：coin.mint(permit overload)
    function _colletWithCoin(
        address token,
        address payer,
        uint amount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (ICoinBase coin) {
        if (amount == 0) {
            revert ErrorInvalidAmount(0);
        }
        coin = _getCoin();

        if (token == GreatLottoCoinAddress) {
            uint underlyingAmount = coin.getAmount(amount);
            if (coin.allowance(payer, address(this)) < underlyingAmount) {
                coin.permit(payer, address(this), underlyingAmount, deadline, v, r, s);
            }
            coin.safeTransferFrom(payer, address(this), underlyingAmount);
        } else {
            coin.mint(token, amount, payer, deadline, v, r, s);
        }
    }

    /// @notice 严格不变量转账。amount==0 早退；前置余额检查；后置 strict equality 校验
    ///         同时 catch silent-fail（transfer 返回 true 但未扣款）与 fee-on-transfer（多扣手续费）两类异常代币。
    function _transferTo(ICoinBase coin, address recipient, uint amount) internal {
        if (amount == 0) return;

        uint _balance = coin.balanceOf(address(this));
        if (_balance < amount) {
            revert ErrorInsufficientBalance(address(coin), address(this), _balance, amount);
        }
        coin.safeTransfer(recipient, amount);
        if (coin.balanceOf(address(this)) != _balance - amount) {
            revert ErrorPaymentUnsuccessful();
        }
    }

    /// @notice 付奖兜底：push 付款失败时按 user 记账（转 pull 模式）。
    /// @dev    internal，供子类在 try/catch 付奖失败分支调用，避免回调 / 交易整体 revert。
    function _recordPendingPayout(address user, uint256 amount) internal {
        _pendingPayouts[user] += amount;
        emit PayoutPending(user, GreatLottoCoinAddress, amount);
    }

    /// @notice 用户提取此前 push 失败而记账的兜底欠款（单一资产币 GLC）。
    /// @dev    pull 支付；noDelegateCall 防止经 delegatecall 篡改记账上下文。
    function claimPayout() external noDelegateCall {
        uint256 amount = _pendingPayouts[msg.sender];
        if (amount == 0) revert ErrorNoPendingPayout();
        _pendingPayouts[msg.sender] = 0;
        _transferTo(_getCoin(), msg.sender, amount);
        emit PayoutClaimed(msg.sender, GreatLottoCoinAddress, amount);
    }

    /// @notice 查询某地址的待提取兜底欠款金额。
    function pendingPayoutOf(address user) external view returns (uint256) {
        return _pendingPayouts[user];
    }

    /// @notice 给指定渠道分润；id 不存在（status==false && chn==address(0)）时 revert，其它情况打款。
    function _channelBenefitTransfer(ICoinBase coin, uint256 benefit, uint256 chnId) internal {
        (bool status, address chn, ) = ISalesChannel(SalesChannelAddress).getChannelById(chnId);
        if (status == false && chn == address(0)) {
            revert ISalesChannel.SalesChannelInvalid(chn);
        }
        _transferTo(coin, chn, benefit);
    }

    /// @notice 给 DAO 利润池打款（语义化 sugar）
    function _daoBenefitTransfer(ICoinBase coin, uint256 benefit) internal {
        _transferTo(coin, DaoBenefitPoolAddress, benefit);
    }

    /// @notice 分润计算（千分比）
    function _getBenefitByRate(uint originAmount, uint16 benefitRate) internal pure returns (uint benefit, uint afterAmount) {
        benefit = originAmount * benefitRate / 1000;
        afterAmount = originAmount - benefit;
    }

    /// @notice 给买家增发治理币（语义化 sugar）
    function _mintDaoCoinToPayer(address payer, uint256 assets) internal {
        IDaoCoin(DaoCoinAddress).mintToUser(payer, assets);
    }

    /// @notice 渠道+DAO 两段分润 pipeline
    /// @param  coin         GLC ICoinBase 引用（由调用方 `_getCoin` 或 `_colletWithCoin` 返回）
    /// @param  amountByCoin 用于计算分润的基数（GLC 计价）
    /// @param  channelId    > 0 时按渠道分别打款（渠道 + sell→DAO）；== 0 时合并打入 DAO（channel + sell 都进 DAO）
    /// @return netAmount    `amountByCoin - channelBenefit - sellBenefit`，由 caller 决定净值去向
    /// @dev    调用方需保证合约 GLC 余额足以覆盖应付分润总额；不足时 `_transferTo` 会 revert
    ///         `ErrorInsufficientBalance`。本 helper 不 emit 单独事件，链下从 ERC20 Transfer 事件推断。
    function _distributeChannelAndDaoBenefits(
        ICoinBase coin,
        uint amountByCoin,
        uint256 channelId
    ) internal returns (uint netAmount) {
        (uint channelBenefit, ) = _getBenefitByRate(amountByCoin, channelBenefitRate);
        (uint sellBenefit, ) = _getBenefitByRate(amountByCoin, sellBenefitRate);

        uint daoBenefit;
        if (channelId > 0) {
            _channelBenefitTransfer(coin, channelBenefit, channelId);
            daoBenefit = sellBenefit;
        } else {
            daoBenefit = sellBenefit + channelBenefit;
        }

        if (daoBenefit > 0) {
            _daoBenefitTransfer(coin, daoBenefit);
        }

        netAmount = amountByCoin - channelBenefit - sellBenefit;
    }

    /// @notice 治理：修改渠道分润率
    /// @dev    每档独立 setter；下游若需新增档（如 invest），自加同形 setter + 事件，不需 override。
    ///         调用方负责保证 `channelBenefitRate + sellBenefitRate <= 1000`（base 不强制 cap）。
    function setChannelBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        if (rate == 0) {
            revert ErrorInvalidAmount(0);
        }
        channelBenefitRate = rate;
        emit ChannelBenefitRateChanged(rate);
        return true;
    }

    /// @notice 治理：修改销售分润率
    /// @dev    每档独立 setter；调用方负责保证两档之和不超过 1000。
    function setSellBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        if (rate == 0) {
            revert ErrorInvalidAmount(0);
        }
        sellBenefitRate = rate;
        emit SellBenefitRateChanged(rate);
        return true;
    }

}
