const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy } = require('../utils/deployTool');

const { parseEther } = ethers;

// BeneficiaryBase  单元测试
describe("BeneficiaryBase", function() {

    // 分润账户 & owner
    const benefitAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    // 买家账户
    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

    const InitializeFixture = async () => {
        // 合约部署
        let contractList = await deploy();

        // 重置时间戳
        await setTimeGap();

        return contractList;

    }

    let contractList;

    let timeGap = 0;

    async function setTimeGap() {
        timeGap =  await time.latest() - getNow();
        console.log('timeGap: '+ timeGap);
    };

    function getNow(){
        return parseInt(new Date().getTime()/1000);
    };

    beforeEach(async () => {
        contractList = await loadFixture(InitializeFixture);
    });

    const benefitTest = async (coin) => {
        let mint = 'mint';
        if(coin == 'investmentCoin' || coin == 'investmentEth'){
            mint = 'mintFor';
        }
        
        // getBeneficiaryList
        it("getBeneficiaryList", async function() {
            // 注入份额
            await contractList[coin][mint](buyerAddress, parseEther('1500000'));
            await contractList[coin][mint](benefitAddress, parseEther('3000000'));
            expect(await contractList[coin].getBeneficiaryList()).to.deep.equal([buyerAddress, benefitAddress]);
        });

        // isBenefitAccount
        it("isBenefitAccount", async function() {
            // 注入份额
            await contractList[coin][mint](buyerAddress, parseEther('5000'));
            expect(await contractList[coin].isBenefitAccount(buyerAddress)).to.equal(false);
            // 分润失败
            expect(await contractList[coin].getBenefitAmount(buyerAddress, parseEther('10000'))).to.equal(0);
            // 注入份额
            await contractList[coin][mint](buyerAddress, parseEther('10000'));
            expect(await contractList[coin].isBenefitAccount(buyerAddress)).to.equal(true);
        });

        // getBenefitAmount
        it("getBenefitAmount", async function() {
            // 注入份额
            await contractList[coin][mint](buyerAddress, parseEther('2000000'));
            await contractList[coin][mint](benefitAddress, parseEther('3000000'));
            expect(await contractList[coin].getBenefitAmount(buyerAddress, parseEther('5000000'))).to.equal(parseEther(5000000n * 2000000n/(2000000n+3000000n) + ''));
        });

        // transfer
        it("Transfer", async function() {
            // 注入份额
            await contractList[coin][mint](benefitAddress, parseEther('20000'));
            expect(await contractList[coin].getBeneficiaryList()).to.deep.equal([benefitAddress]);
            // 转移
            await contractList[coin].transfer(buyerAddress, parseEther('5000'));
            expect(await contractList[coin].getBeneficiaryList()).to.deep.equal([benefitAddress]);
            await contractList[coin].transfer(buyerAddress, parseEther('5000'));
            expect(await contractList[coin].getBeneficiaryList()).to.deep.equal([benefitAddress, buyerAddress]);
            await contractList[coin].transfer(buyerAddress, parseEther('5000'));
            expect(await contractList[coin].getBeneficiaryList()).to.deep.equal([buyerAddress]);

        });

    }

    // 分润相关测试
    describe("DaoCoin", async function () {
        await benefitTest('daoCoin');
    });


});


