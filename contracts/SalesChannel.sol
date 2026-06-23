// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ISalesChannel.sol";
import "./interfaces/ICoinBase.sol";

import "./base/AccessControlPartnerContract.sol";
import "./base/NoDelegateCall.sol";
import "./base/DeadLine.sol";

/// @title SalesChannel
/// @notice 销售渠道注册表 + 渠道分润托管账本。渠道方自助注册/改名；PrizePool（PARTNER）把渠道分润
///         转入本合约并经 `creditChannel` 按 chnId 记账；渠道方经 `withdraw` 自提（pull payment）。
/// @dev    持有 GLC（ICoinBase），偿付能力恒满足 `balanceOf >= _totalAccrued - _totalWithdrawn`。
///         记账入口 `creditChannel` 受 PARTNER_CONTRACT_ROLE 守护，只授审计过、保证「先转账后记账等额」
///         的 PrizePool 合约。
contract SalesChannel is ISalesChannel, AccessControlPartnerContract, NoDelegateCall, DeadLine {
    using SafeERC20 for ICoinBase;

    // 分页查询单页上限
    uint256 public constant MAX_CHANNEL_PAGE = 20;

    // 资产币地址（GLC）
    address public immutable GreatLottoCoinAddress;

    uint256 private _nextId = 1;

    // 销售渠道管理
    mapping(uint chnId => ChannelInfo) private _channel;

    // 销售渠道地址管理
    mapping(address chn => uint chnId) private _channelAddress;

    // 单渠道累计入账（含已提）
    mapping(uint256 chnId => uint256) private _accrued;
    // 单渠道累计已提
    mapping(uint256 chnId => uint256) private _withdrawn;

    // 全局累计入账（仅 creditChannel 自增）= Σ _accrued
    uint256 private _totalAccrued;
    // 全局累计已提（仅 withdraw 自增）= Σ _withdrawn
    uint256 private _totalWithdrawn;

    constructor(address coin, address _owner) AccessControlPartnerContract(_owner) {
        GreatLottoCoinAddress = coin;
    }

    // ---------------------------------------------------------------------
    // 渠道注册 / 改名
    // ---------------------------------------------------------------------

    // 注册销售渠道
    function registerChannel(string memory name, uint256 deadline) external noDelegateCall checkDeadline(deadline) returns (bool) {
        address chnAddr = msg.sender;

        if (_channelAddress[chnAddr] > 0) {
            revert SalesChannelAlreadyExists(chnAddr);
        }

        uint chnId = _nextId++;

        _channelAddress[chnAddr] = chnId;

        _channel[chnId] = ChannelInfo({
            id: chnId,
            chn: chnAddr,
            name: name
        });

        emit SalesChannelRegistered(chnAddr, chnId, name);

        return true;
    }

    // 更改渠道名称
    function changeChannelName(string memory name, uint256 deadline) external noDelegateCall checkDeadline(deadline) returns (bool) {
        address chnAddr = msg.sender;

        uint chnId = _channelAddress[chnAddr];
        if (chnId == 0) {
            revert SalesChannelNotExists(chnAddr);
        }

        _channel[chnId].name = name;

        emit SalesChannelNameChanged(chnAddr, chnId, name);

        return true;
    }

    // ---------------------------------------------------------------------
    // 视图查询
    // ---------------------------------------------------------------------

    // 按地址查询渠道
    function getChannelByAddr(address chn) external view returns (uint, string memory) {
        if (chn == address(0)) {
            return (0, '');
        }
        uint chnId = _channelAddress[chn];
        if (chnId == 0) {
            return (0, '');
        }
        return (chnId, _channel[chnId].name);
    }

    // 按 id 查询渠道
    function getChannelById(uint chnId) external view returns (address, string memory) {
        ChannelInfo memory chnInfo = _channel[chnId];
        if (chnInfo.chn == address(0)) {
            return (address(0), '');
        }
        return (chnInfo.chn, chnInfo.name);
    }

    // 获取销售渠道数量
    function getChannelCount() external view returns (uint) {
        return _nextId - 1;
    }

    /// @notice 分页批量读取渠道（按 chnId 升序，含 startId，最多 count 个，实际长度按剩余裁剪）。
    function getChannelsPaged(uint256 startId, uint256 count) external view returns (ChannelInfo[] memory) {
        if (count > MAX_CHANNEL_PAGE) {
            revert SalesChannelPageTooLarge(count);
        }
        if (startId == 0) {
            startId = 1;
        }
        uint256 lastId = _nextId - 1;
        if (count == 0 || startId > lastId) {
            return new ChannelInfo[](0);
        }
        uint256 end = startId + count - 1;
        if (end > lastId) {
            end = lastId;
        }
        uint256 len = end - startId + 1;
        ChannelInfo[] memory list = new ChannelInfo[](len);
        for (uint256 i = 0; i < len; i++) {
            list[i] = _channel[startId + i];
        }
        return list;
    }

    // ---------------------------------------------------------------------
    // 分润记账 / 自提
    // ---------------------------------------------------------------------

    /// @notice PrizePool（PARTNER）在分润时调用：把已转入本合约的渠道分润按 chnId 记账。
    /// @dev    前置条件（MUST）：调用方已先把等额 amount GLC safeTransfer 入本合约，且金额一致、顺序为
    ///         「先转账后记账」。本函数不校验到账（信任 PARTNER），故 PARTNER_CONTRACT_ROLE 只授审计过的
    ///         PrizePool 合约，绝不授 EOA。
    function creditChannel(uint256 chnId, uint256 amount) external onlyRole(PARTNER_CONTRACT_ROLE) {
        _accrued[chnId] += amount;
        _totalAccrued += amount;
        emit SalesChannelCredited(chnId, amount);
    }

    /// @notice 渠道方提取累计分润（pull payment）。提到 msg.sender 自己，不接受任意 to。
    /// @dev    CEI：先更新账本（_withdrawn / _totalWithdrawn）再 safeTransfer。
    function withdraw() external noDelegateCall {
        uint256 chnId = _channelAddress[msg.sender];
        uint256 amount = _accrued[chnId] - _withdrawn[chnId];
        if (amount == 0) {
            revert SalesChannelNothingToWithdraw(chnId);
        }
        _withdrawn[chnId] += amount;
        _totalWithdrawn += amount;
        ICoinBase(GreatLottoCoinAddress).safeTransfer(msg.sender, amount);
        emit SalesChannelWithdrawn(chnId, msg.sender, amount);
    }

    // ---------------------------------------------------------------------
    // 账本查询
    // ---------------------------------------------------------------------

    /// @notice 某渠道当前待提取分润（_accrued - _withdrawn）。
    function pendingOf(uint256 chnId) external view returns (uint256) {
        return _accrued[chnId] - _withdrawn[chnId];
    }

    /// @notice 某渠道历史累计入账分润（含已提）。
    function accruedOf(uint256 chnId) external view returns (uint256) {
        return _accrued[chnId];
    }

    /// @notice 某渠道历史累计已提分润。
    function withdrawnOf(uint256 chnId) external view returns (uint256) {
        return _withdrawn[chnId];
    }

    /// @notice 平台全局累计入账分润总额（Σ accruedOf）。
    function totalAccrued() external view returns (uint256) {
        return _totalAccrued;
    }

    /// @notice 平台全局累计已提分润总额（Σ withdrawnOf）。
    function totalWithdrawn() external view returns (uint256) {
        return _totalWithdrawn;
    }

}
