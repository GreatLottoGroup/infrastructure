// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ISalesChannel.sol";
import "./interfaces/ICoinBase.sol";

import "./base/AccessControlPartnerContract.sol";
import "./base/NoDelegateCall.sol";
import "./base/DeadLine.sol";

/// @title SalesChannel
/// @notice Sales-channel registry plus a custodial channel-benefit ledger. Channels self-register and rename;
///         the PrizePool (PARTNER) transfers channel benefit into this contract and records it per channel id
///         via `creditChannel`; channels withdraw it themselves via `withdraw` (pull payment).
/// @dev    Holds GLC (`ICoinBase`); solvency always holds: `balanceOf >= _totalAccrued - _totalWithdrawn`.
///         The crediting entry `creditChannel` is guarded by `PARTNER_CONTRACT_ROLE` and is only granted to the
///         audited PrizePool contract, which guarantees "transfer an equal amount before crediting".
contract SalesChannel is ISalesChannel, AccessControlPartnerContract, NoDelegateCall, DeadLine, ReentrancyGuard {
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

    /// @inheritdoc ISalesChannel
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

    /// @inheritdoc ISalesChannel
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

    /// @inheritdoc ISalesChannel
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

    /// @inheritdoc ISalesChannel
    function getChannelById(uint chnId) external view returns (address, string memory) {
        ChannelInfo memory chnInfo = _channel[chnId];
        if (chnInfo.chn == address(0)) {
            return (address(0), '');
        }
        return (chnInfo.chn, chnInfo.name);
    }

    /// @inheritdoc ISalesChannel
    function getChannelCount() external view returns (uint) {
        return _nextId - 1;
    }

    /// @inheritdoc ISalesChannel
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

    /// @inheritdoc ISalesChannel
    function creditChannel(uint256 chnId, uint256 amount) external onlyRole(PARTNER_CONTRACT_ROLE) {
        _accrued[chnId] += amount;
        _totalAccrued += amount;
        emit SalesChannelCredited(chnId, amount);
    }

    /// @inheritdoc ISalesChannel
    /// @dev CEI: updates the ledger (`_withdrawn` / `_totalWithdrawn`) before `safeTransfer`; pays `msg.sender`
    ///      only (no arbitrary recipient).
    function withdraw() external noDelegateCall nonReentrant {
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

    /// @inheritdoc ISalesChannel
    function pendingOf(uint256 chnId) external view returns (uint256) {
        return _accrued[chnId] - _withdrawn[chnId];
    }

    /// @inheritdoc ISalesChannel
    function accruedOf(uint256 chnId) external view returns (uint256) {
        return _accrued[chnId];
    }

    /// @inheritdoc ISalesChannel
    function withdrawnOf(uint256 chnId) external view returns (uint256) {
        return _withdrawn[chnId];
    }

    /// @inheritdoc ISalesChannel
    function totalAccrued() external view returns (uint256) {
        return _totalAccrued;
    }

    /// @inheritdoc ISalesChannel
    function totalWithdrawn() external view returns (uint256) {
        return _totalWithdrawn;
    }

}
