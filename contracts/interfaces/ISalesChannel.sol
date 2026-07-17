// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;


/// @title ISalesChannel
/// @notice Contract interface for the sales-channel registry and channel benefit ledger: channels self-register
///         and rename; the prize pool (PARTNER) credits channel benefits; channels withdraw them (pull payment).
/// @dev    All ledger amounts are in wei of the settlement currency GLC. `deadline` parameters are unix
///         timestamps in seconds (transaction deadline).
interface ISalesChannel {

    /**
     * @dev SalesChannel: channel already exists
     */
    error SalesChannelAlreadyExists(address);

    /**
     * @dev SalesChannel: channel is not exists
     */
    error SalesChannelNotExists(address);

    /**
     * @dev SalesChannel: The channel is invalid
     */
    error SalesChannelInvalid(address);

    /**
     * @dev SalesChannel: paged query count exceeds MAX_CHANNEL_PAGE
     */
    error SalesChannelPageTooLarge(uint256);

    /**
     * @dev SalesChannel: nothing to withdraw for this channel
     */
    error SalesChannelNothingToWithdraw(uint256);

    struct ChannelInfo {
        uint256 id;
        address chn;
        string name;
    }

    // 渠道注册事件
    event SalesChannelRegistered(address indexed addr, uint256 id, string name);

    // 渠道名称变更事件
    event SalesChannelNameChanged(address indexed addr, uint256 id, string name);

    // 渠道分润入账事件（PrizePool 经 creditChannel 触发）
    event SalesChannelCredited(uint256 indexed id, uint256 amount);

    // 渠道分润提取事件（渠道方自提）
    event SalesChannelWithdrawn(uint256 indexed id, address indexed chn, uint256 amount);

    /// @notice Register the caller (`msg.sender`) as a new sales channel.
    /// @dev    Reverts `SalesChannelAlreadyExists` if the caller is already registered; subject to `deadline`.
    /// @param  name     Human-readable display name for the channel.
    /// @param  deadline Transaction deadline, a unix timestamp in seconds.
    /// @return True on success.
    function registerChannel(string memory name, uint256 deadline) external returns (bool);

    /// @notice Change the display name of the caller's registered channel.
    /// @dev    Reverts `SalesChannelNotExists` if the caller has no channel; subject to `deadline`.
    /// @param  name     New human-readable display name.
    /// @param  deadline Transaction deadline, a unix timestamp in seconds.
    /// @return True on success.
    function changeChannelName(string memory name, uint256 deadline) external returns (bool);

    /// @notice Look up a channel by its address.
    /// @param  chn The channel address to look up.
    /// @return The channel id (0 if not found).
    /// @return The channel display name ("" if not found).
    function getChannelByAddr(address chn) external view returns (uint, string memory);

    /// @notice Look up a channel by its id.
    /// @param  chnId The channel id to look up.
    /// @return The channel address (address(0) if not found).
    /// @return The channel display name ("" if not found).
    function getChannelById(uint chnId) external view returns (address, string memory);

    /// @notice The number of registered channels.
    /// @return The channel count.
    function getChannelCount() external view returns (uint);

    /// @notice Read a page of channels by ascending id (starting at `startId`, up to `count`, clamped to the tail).
    /// @dev    Reverts `SalesChannelPageTooLarge` when `count` exceeds the per-page limit `MAX_CHANNEL_PAGE`.
    /// @param  startId The first channel id to include (treated as 1 when 0 is passed).
    /// @param  count   Maximum number of channels to return.
    /// @return The page of `ChannelInfo` entries (length clamped to the number of remaining channels).
    function getChannelsPaged(uint256 startId, uint256 count) external view returns (ChannelInfo[] memory);

    /// @notice Credit accrued benefit to a channel's ledger. Restricted to `PARTNER_CONTRACT_ROLE`.
    /// @dev    Precondition (MUST): the caller has already `safeTransfer`ed an equal `amount` of GLC into this
    ///         contract, transfer before crediting. This function does not verify receipt (it trusts the PARTNER).
    /// @param  chnId  The channel id to credit.
    /// @param  amount The benefit amount in wei (GLC).
    function creditChannel(uint256 chnId, uint256 amount) external;

    /// @notice Withdraw the caller's channel's accrued-but-unwithdrawn benefit (pull payment) to `msg.sender`.
    /// @dev    Reverts `SalesChannelNothingToWithdraw` when the balance is zero.
    function withdraw() external;

    /// @notice The channel's currently withdrawable benefit (accrued minus withdrawn).
    /// @param  chnId The channel id to query.
    /// @return The pending amount in wei (GLC).
    function pendingOf(uint256 chnId) external view returns (uint256);

    /// @notice The channel's lifetime accrued benefit (including already withdrawn).
    /// @param  chnId The channel id to query.
    /// @return The accrued amount in wei (GLC).
    function accruedOf(uint256 chnId) external view returns (uint256);

    /// @notice The channel's lifetime withdrawn benefit.
    /// @param  chnId The channel id to query.
    /// @return The withdrawn amount in wei (GLC).
    function withdrawnOf(uint256 chnId) external view returns (uint256);

    /// @notice The platform-wide total accrued benefit across all channels (Σ accruedOf).
    /// @return The total accrued amount in wei (GLC).
    function totalAccrued() external view returns (uint256);

    /// @notice The platform-wide total withdrawn benefit across all channels (Σ withdrawnOf).
    /// @return The total withdrawn amount in wei (GLC).
    function totalWithdrawn() external view returns (uint256);

}
