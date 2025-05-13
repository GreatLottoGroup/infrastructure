const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy } = require('../utils/deployTool');

// Callable  单元测试
describe("AccessControlPartnerContract", function() {

    // 买家账户
    const buyerAddress = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';
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
        ({greatLottoCoin, daoBenefitPool} = await loadFixture(InitializeFixture));
    });
        
    // grantRole
    describe("grantRole", function() {

        it("Should revert if new account is zero address", async function() {
            await expect(greatLottoCoin.grantRole(PARTNER_CONTRACT_ROLE, ethers.ZeroAddress)).to.be.revertedWithCustomError(greatLottoCoin, "ErrorZeroAddress").withArgs();
        });
        
        it("Should revert if new account is not a contract address", async function() {
            await expect(greatLottoCoin.grantRole(PARTNER_CONTRACT_ROLE, buyerAddress)).to.be.revertedWithCustomError(greatLottoCoin, "ErrorInvalidAddress").withArgs(buyerAddress);
        });

        it("Should Grant Role", async function() {
            await greatLottoCoin.grantRole(PARTNER_CONTRACT_ROLE, daoBenefitPool.address);
            expect(await greatLottoCoin.hasRole(PARTNER_CONTRACT_ROLE, daoBenefitPool.address)).to.be.true;
        });

    });
    
});
