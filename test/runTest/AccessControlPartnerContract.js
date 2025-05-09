const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy } = require('../utils/deployTool');

// Callable  单元测试
describe("AccessControlPartnerContract", function() {

    // 买家账户
    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
    const PARTNER_CONTRACT_ROLE = ethers.solidityPackedKeccak256(["string"], ["PARTNER_CONTRACT_ROLE"]);

    const InitializeFixture = async () => {
        // 合约部署
        let contractList = await deploy();
        
        // 重置时间戳
        await setTimeGap();

        return contractList;

    }

    let greatLottoCoin;

    let timeGap = 0;

    async function setTimeGap() {
        timeGap =  await time.latest() - getNow();
        console.log('timeGap: '+ timeGap);
    };
    function getNow(){
        return parseInt(new Date().getTime()/1000);
    };

    beforeEach(async () => {
        ({greatLottoCoin} = await loadFixture(InitializeFixture));
    });
        
    // grantRole
    describe("grantRole", function() {

        it("Should revert if new account is zero address", async function() {
            await expect(greatLottoCoin.grantRole(PARTNER_CONTRACT_ROLE, ethers.ZeroAddress)).to.be.revertedWithCustomError(greatLottoCoin, "ErrorZeroAddress").withArgs();
        });
        
        it("Should revert if new account is not a contract address", async function() {
            await expect(greatLottoCoin.grantRole(PARTNER_CONTRACT_ROLE, buyerAddress)).to.be.revertedWithCustomError(greatLottoCoin, "ErrorInvalidAddress").withArgs(buyerAddress);
        });
    });
    
});
