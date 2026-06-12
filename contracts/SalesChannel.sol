// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import '@openzeppelin/contracts/access/Ownable.sol';

import "./interfaces/ISalesChannel.sol";

import "./base/NoDelegateCall.sol";
import "./base/DeadLine.sol";

// 销售渠道管理合约
contract SalesChannel is ISalesChannel, Ownable, NoDelegateCall, DeadLine{

    uint256 private _nextId = 1;

    // 销售渠道管理
    mapping(uint chnId => ChannelInfo) private _channel;

    // 销售渠道地址管理 
    mapping (address chn => uint chnId) _channelAddress;

    constructor(address _owner) Ownable(_owner == address(0) ? _msgSender() : _owner) {}

    // 注册销售渠道
    function registerChannel(string memory name, uint256 deadline)  external noDelegateCall checkDeadline(deadline) returns (bool) {

        address chnAddr = msg.sender;
        
        if(_channelAddress[chnAddr] > 0){
            revert SalesChannelAlreadyExists(chnAddr);
        }

        uint chnId = _nextId++;

        _channelAddress[chnAddr] = chnId;

        _channel[chnId] = ChannelInfo({
            id: chnId,
            chn: chnAddr,
            name: name,
            status: true
        });

        // 触发事件
        emit SalesChannelRegistered(chnAddr, chnId, name);

        return true;
        
    }

    // 更改渠道名称
    function changeChannelName(string memory name, uint256 deadline)  external noDelegateCall checkDeadline(deadline) returns (bool) {

        address chnAddr = msg.sender;

        if(_channelAddress[chnAddr] == 0){
            revert SalesChannelNotExists(chnAddr);
        }

        uint chnId = _channelAddress[chnAddr];
        
        if(_channel[chnId].status == false){
            revert SalesChannelAlreadyDisabled(chnAddr);
        }

        _channel[chnId].name = name;

        // 触发事件
        emit SalesChannelNameChanged(chnAddr, chnId, name);

        return true;
        
    }

    // 销售渠道状态
    function getChannelByAddr(address chn) external view returns (bool, uint, string memory) {
        if(chn == address(0)){
            return (false, 0, '');
        }else{
            uint chnId = _channelAddress[chn];
            if(chnId > 0){
                ChannelInfo memory chnInfo = _channel[chnId];
                return (chnInfo.status, chnId, chnInfo.name);
            }else{
                return (false, 0, '');
            }
        }
    }

    // 销售渠道状态
    function getChannelById(uint chnId) external view returns (bool, address, string memory) {
        if(chnId > 0){
            ChannelInfo memory chnInfo = _channel[chnId];
            if(chnInfo.chn == address(0)){
                return (false, address(0), '');
            }else{
                return (chnInfo.status, chnInfo.chn, chnInfo.name);
            }
        }else{
            return (false, address(0), '');
        }  
    }   

    // 获取销售渠道数量
    function getChannelCount() external view returns (uint) {
        return _nextId - 1; 
    }   

    // 禁用销售渠道
    function disableChannel(uint chnId)  external onlyOwner returns (bool) {
        if(_channel[chnId].chn == address(0)){
            revert SalesChannelNotExists(address(0));
        }
        if(_channel[chnId].status == false){
            revert SalesChannelAlreadyDisabled(_channel[chnId].chn);
        }

        _channel[chnId].status = false;

        // 触发事件
        emit SalesChannelDisabled(chnId, _channel[chnId].chn);

        return true;
    }

    // 解禁销售渠道
    function enableChannel(uint chnId)  external onlyOwner returns (bool){
        if(_channel[chnId].chn == address(0)){
            revert SalesChannelNotExists(address(0));
        }
        if(_channel[chnId].status == true){
            revert SalesChannelAlreadyEnabled(_channel[chnId].chn);
        }

        _channel[chnId].status = true;

        // 触发事件
        emit SalesChannelEnabled(chnId, _channel[chnId].chn);

        return true;

    }



}