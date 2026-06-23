// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;


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

    function registerChannel(string memory name, uint256 deadline) external returns (bool);

    function changeChannelName(string memory name, uint256 deadline) external returns (bool);

    function getChannelByAddr(address chn) external view returns (uint, string memory);

    function getChannelById(uint chnId) external view returns (address, string memory);

    function getChannelCount() external view returns (uint);

    function getChannelsPaged(uint256 startId, uint256 count) external view returns (ChannelInfo[] memory);

    function creditChannel(uint256 chnId, uint256 amount) external;

    function withdraw() external;

    function pendingOf(uint256 chnId) external view returns (uint256);

    function accruedOf(uint256 chnId) external view returns (uint256);

    function withdrawnOf(uint256 chnId) external view returns (uint256);

    function totalAccrued() external view returns (uint256);

    function totalWithdrawn() external view returns (uint256);

}
