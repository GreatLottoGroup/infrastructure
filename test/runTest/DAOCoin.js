const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy} = require('../utils/deployTool');
const { getDaoShares } = require('../utils/newConvert');
const { parseEther } = ethers;

// DaoCoin  单元测试
describe("DaoCoin", function() {

    // 买家账户
    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
    const buyer2Address = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';

    const InitializeFixture = async () => {
        // 合约部署
        let contractList = await deploy();

        // 重置时间戳
        await setTimeGap();

        return contractList;

    }

    let daoCoin;

    let timeGap = 0;

    async function setTimeGap() {
        timeGap =  await time.latest() - getNow();
        console.log('timeGap: '+ timeGap);
    };

    function getNow(){
        return parseInt(new Date().getTime()/1000);
    };

    beforeEach(async () => {
        ({daoCoin, partnerTest} = await loadFixture(InitializeFixture));
    });

    describe("Change Price", function() {

        // 修改初始价格
        it("Should revert if initialPrice is 0", async function() {
            await expect(daoCoin.changePrice(0)).to.be.revertedWithCustomError(daoCoin, "ErrorInvalidAmount").withArgs(0);
        });

        it("Success To Change Price", async function() {
            let price = parseEther('200');
            await expect(daoCoin.changePrice(price)).to.emit(daoCoin, "PriceChanged").withArgs(price);
            expect(await daoCoin.coinPrice()).to.be.equal(price);
        });

        // 旧 isEth 签名已下线（compile 期会失败）
        it("Should not have eth-priced selector", async function() {
            expect(daoCoin.interface.fragments.find(f => f.name === 'changePrice' && f.inputs.length === 2)).to.be.undefined;
            expect(daoCoin.coinPriceEth).to.be.undefined;
        });

    });

    // mint测试
    describe("Mint", function() {

        // mint
        it("Mint", async function() {
            // 注入份额
            await daoCoin.mint(buyerAddress,  parseEther('10000'));
            expect(await daoCoin.balanceOf(buyerAddress)).to.equal(parseEther('10000'));
            expect(await daoCoin.totalSupply()).to.equal(parseEther('10000'));
        });

        // mintToUser
        it("MintToUser", async function() {

            // 注入份额
            await partnerTest.daoMintToUser(buyerAddress,  parseEther('1000'));
            await partnerTest.daoMintToUser(buyer2Address,  parseEther('500'));

            expect(await daoCoin.balanceOf(buyerAddress)).to.equal(getDaoShares(parseEther('1000')));
            expect(await daoCoin.balanceOf(buyer2Address)).to.equal(getDaoShares(parseEther('500')));
        });

        // 旧的 isEth 签名已 compile-error / 不存在
        it("Should not have isEth mintToUser selector", async function() {
            const fragment = daoCoin.interface.fragments.find(f => f.name === 'mintToUser' && f.inputs.length === 3);
            expect(fragment).to.be.undefined;
        });

    });

});
