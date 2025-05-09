const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy } = require('../utils/deployTool');

// SalesChannel  单元测试
describe("SalesChannel", function() {

    const ownerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

    const InitializeFixture = async () => {
        // 合约部署
        let contractList = await deploy();
        
        // 重置时间戳
        await setTimeGap();

        return contractList;

    }

    let salesChannel;

    let timeGap = 0;

    async function setTimeGap() {
        timeGap =  await time.latest() - getNow();
        console.log('timeGap: '+ timeGap);
    };
    function deadline(){
        return getNow() + timeGap + 1200;
    };
    function getNow(){
        return parseInt(new Date().getTime()/1000);
    };

    beforeEach(async () => {
        ({salesChannel} = await loadFixture(InitializeFixture));
    });

    let cname = 'test';

    // 渠道注册
    async function registerChannel(name) {
        let chnId;

        let getChnId = (id) => {
            chnId = id;
            return true;
        };

        await expect(salesChannel.registerChannel(name, deadline())).to.emit(salesChannel, 'SalesChannelRegistered').withArgs(ownerAddress, getChnId, name);

        return chnId;
    }

    // 注册销售渠道
    describe("RegisterSalesChannel", function() {

        // 注册销售渠道，返回渠道id
        it("Should registerSalesChannel", async function() {
            let chnId = await registerChannel(cname);

            expect(await salesChannel.getChannelById(chnId)).to.deep.equal([true, ownerAddress, cname]);

            expect(await salesChannel.getChannelByAddr(ownerAddress)).to.deep.equal([true, chnId, cname]);

            expect(await salesChannel.getChannelCount()).to.deep.equal(1n);

            // 渠道已存在
            await expect(salesChannel.registerChannel('test2', deadline())).to.be.revertedWithCustomError(salesChannel, 'SalesChannelAlreadyExists');
            
        });

        // 查询渠道的异常情况
        it("Should revert when getChannelById and getChannelByAddr params error", async function() {
             
            expect(await salesChannel.getChannelById(0)).to.deep.equal([false, ethers.ZeroAddress, '']);

            expect(await salesChannel.getChannelByAddr(ethers.ZeroAddress)).to.deep.equal([false, 0, '']);

            expect(await salesChannel.getChannelByAddr(buyerAddress)).to.deep.equal([false, 0, '']);
        });

    });

    // 渠道管理
    describe("SalesChannelManagement", function() {

        // 修改渠道名字
        it("Should change channel name", async function() {
            let chnId = await registerChannel(cname);
            let chengeName = 'test2';
            
            // 成功修改
            await expect(salesChannel.changeChannelName(chengeName, deadline())).to.emit(salesChannel, 'SalesChannelNameChanged').withArgs(ownerAddress, chnId, chengeName);
            
            // 禁用渠道不能修改
            await salesChannel.disableChannel(chnId);
            await expect(salesChannel.changeChannelName(chengeName, deadline())).to.be.revertedWithCustomError(salesChannel, 'SalesChannelAlreadyDisabled');

            // 渠道不存在不能修改
            let buyerSalesChannelContract = await salesChannel.connect(await ethers.getImpersonatedSigner(buyerAddress));
            await expect(buyerSalesChannelContract.changeChannelName(chengeName, deadline())).to.be.revertedWithCustomError(buyerSalesChannelContract, 'SalesChannelNotExists');
        });

        // 禁用及启用渠道
        it("Should disableChannel and enableChannel", async function() {

            let chnId = await registerChannel(cname);

            // 禁用渠道
            await expect(salesChannel.disableChannel(chnId)).to.emit(salesChannel, 'SalesChannelDisabled').withArgs(chnId, ownerAddress);

            // 禁用效果检查
            expect(await salesChannel.getChannelById(chnId)).to.deep.equal([false, ownerAddress, cname]);

            // 禁用revert
            await expect(salesChannel.disableChannel(chnId)).to.be.revertedWithCustomError(salesChannel, 'SalesChannelAlreadyDisabled');
            await expect(salesChannel.disableChannel(10)).to.be.revertedWithCustomError(salesChannel, 'SalesChannelNotExists');

            // 启用渠道
            await expect(salesChannel.enableChannel(chnId)).to.emit(salesChannel, 'SalesChannelEnabled').withArgs(chnId, ownerAddress);

            // 启用效果检查
            expect(await salesChannel.getChannelById(chnId)).to.deep.equal([true, ownerAddress, cname]);

            // 启用revert
            await expect(salesChannel.enableChannel(chnId)).to.be.revertedWithCustomError(salesChannel, 'SalesChannelAlreadyEnabled');
            await expect(salesChannel.enableChannel(10)).to.be.revertedWithCustomError(salesChannel, 'SalesChannelNotExists');


        });


    });
        

});


