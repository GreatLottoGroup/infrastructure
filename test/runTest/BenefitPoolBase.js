const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy } = require('../utils/deployTool');
const { benefitCompute } = require('../utils/benefit');

const { parseEther } = ethers;

// BenefitPoolBase  单元测试
describe("BenefitPoolBase", function() {

    // 买家账户
    const buyerList = [
        '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC',
        '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
        '0xA3ac37647cF032574e99b78bEB9fb573be9929F5',
        '0x2e730F4Ac3A0767a0E1A713010aed9F77046b67e'
    ]
    const sharesList = [5000, 200*10**4, 300*10**4, 400*10**4, 500*10**4];

    // 执行账户
    const executeBenefitAddress = '0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65';

    const InitializeFixture = async () => {
        // 合约部署
        let contractList = await deploy();

        // 重置时间戳
        await setTimeGap();

        await addShares(contractList.daoCoin, 'mint');

        return contractList;

    }

    let greatLottoCoin;
    let daoCoin;
    let daoBenefitPool;

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

    let executorDaoBenefitPoolContract;

    beforeEach(async () => {
        ({greatLottoCoin, daoCoin, daoBenefitPool} = await loadFixture(InitializeFixture));
        executorDaoBenefitPoolContract = daoBenefitPool.connect(await ethers.getImpersonatedSigner(executeBenefitAddress));
    });

    // 最小分润份额 1w
    let BenefitMinShares = parseEther('10000');

    let addShares = async (govCoinContract, mint) => {
        for(let i = 0; i < buyerList.length; i++){
            await govCoinContract[mint](buyerList[i], parseEther(sharesList[i] +''));
        }
    }

    let addBenefit = async (coinContract, poolContract, amount) => {
        await coinContract.mintFor(poolContract.address, amount);
    }


    describe("BenefitPool Check", function() {

        // 分润池为空
        it("Should revert if no benefit", async function() {
            await expect(executorDaoBenefitPoolContract.executeBenefit(deadline())).to.be.revertedWithCustomError(executorDaoBenefitPoolContract, 'BenefitPoolNoBenefit');
        });

        // 旧 isEth 签名已下线
        it("Should not have isEth executeBenefit selector", async function() {
            const fragment = daoBenefitPool.interface.fragments.find(f => f.name === 'executeBenefit' && f.inputs.length === 2);
            expect(fragment).to.be.undefined;
        });

    });

    // 执行分润
    describe("ExecuteBenefit", function() {

        let checkBefore = async (coinContract, poolContract) => {
            // buyerBalance
            let buyerBalanceBefore = []
            for(let i = 0; i < buyerList.length; i++){
                buyerBalanceBefore.push(await coinContract.balanceOf(buyerList[i]));
            }
            // poolBalance
            let poolBalanceBefore = await coinContract.balanceOf(poolContract.address);

            return [buyerBalanceBefore, poolBalanceBefore]
        }

        let executeBenefit = async (executorContract, poolContract, coinContract, govCoinContract) => {
            const poolAmount = 10*10**4
            await addBenefit(coinContract, poolContract, parseEther(poolAmount + ''));
            let totalSupply = await govCoinContract.totalSupply();
            let [benefitList, totalBenefitAmount] = await benefitCompute(sharesList, poolAmount, totalSupply, BenefitMinShares);

            let [buyerBalanceBefore, poolBalanceBefore] = await checkBefore(coinContract, poolContract);

            // 执行分润
            await expect(executorContract.executeBenefit(deadline())).to.be.emit(executorContract, 'BenefitExecuted').withArgs(executeBenefitAddress, totalBenefitAmount);

            // 检查
            for(let i = 0; i < buyerList.length; i++){
                expect(await coinContract.balanceOf(buyerList[i])).to.equal(buyerBalanceBefore[i] + benefitList[i]);
            }
            expect(await coinContract.balanceOf(poolContract)).to.equal(poolBalanceBefore - totalBenefitAmount);
        };

        // executeBenefit
        it("Should executeBenefit by daoBenefitPool coin", async function() {
            await executeBenefit(executorDaoBenefitPoolContract, daoBenefitPool, greatLottoCoin, daoCoin)
        });

    });

});
