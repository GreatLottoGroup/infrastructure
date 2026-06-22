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
     * @dev SalesChannel: channel not found or already disabled
     */
    error SalesChannelAlreadyDisabled(address);

    /**
     * @dev SalesChannel: channel not found or already enabled
     */
    error SalesChannelAlreadyEnabled(address);

    /**
     * @dev SalesChannel: The channel is invalid
     */
    error SalesChannelInvalid(address);

    struct ChannelInfo {
        uint256 id;
        address chn;  
        string name;  
        bool status; 
    }

    // 渠道注册事件
    event SalesChannelRegistered(address indexed addr, uint256 id, string name);
    
    // 渠道名称变更事件
    event SalesChannelNameChanged(address indexed addr, uint256 id, string name);
    
    // 渠道禁用事件
    event SalesChannelDisabled(uint256 indexed id, address addr);

    // 渠道启用事件
    event SalesChannelEnabled(uint256 indexed id, address addr);

    function registerChannel(string memory name, uint256 deadline) external returns (bool);

    function changeChannelName(string memory name, uint256 deadline) external returns (bool);

    function getChannelByAddr(address chn) external view returns (bool, uint, string memory);

    function getChannelById(uint chnId) external view returns (bool, address, string memory);

    function getChannelCount() external view returns (uint);

    function disableChannel(uint chnId)  external returns (bool);

    function enableChannel(uint chnId)  external returns (bool);


}
