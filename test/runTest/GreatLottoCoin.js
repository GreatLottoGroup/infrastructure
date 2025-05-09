const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy } = require('../utils/deployTool');
const getCoin = require('../utils/getCoin');
const { getSignMessageByCoin, getSignMessage } = require('../utils/permitUtils');

const { parseEther, parseUnits } = ethers;

// GreatLotto coin  集成测试
describe("GreatLottoCoin", function() {

    // owner
    const ownerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    // 买家账户
    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

    const InitializeFixture = async () => {
        // 合约部署
        let contractList = await deploy();

        // 买入 1000 USDT
        await getCoin.getUSDTCoin(buyerAddress, 1000);
        // 买入 1000 USDC
        await getCoin.getUSDCCoin(buyerAddress, 1000);
        // 买入 1000 DAI
        await getCoin.getDAICoin(buyerAddress, 1000);

        // 重置时间戳
        await setTimeGap();
     
        return contractList;

    }

    let partnerTest;
    let greatLottoCoin;

    // localCoin decimals
    let decimalsLocalCoin = 18;

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
        ({partnerTest, greatLottoCoin} = await loadFixture(InitializeFixture));
    });

    let mintCoin = async (tokenName, amount) => {
        // 授权
        await getCoin['approve' + tokenName + 'Coin'](buyerAddress, greatLottoCoin.address, amount);
        // mint
        await partnerTest.coinMint(getCoin[tokenName + '_ADDRESS'], amount, buyerAddress)
    }

    // 测试Mint
    describe("mint", function() {
        let checkBefore = async (tokenName) => {
            // 准备
            let beforeData = {};
            beforeData.coinBalance = await getCoin['get' + tokenName + 'Balance'](greatLottoCoin.address);
            beforeData.buyerBalance = await greatLottoCoin.balanceOf(buyerAddress);
            return beforeData;
        }

        let checkMintCoin = async (tokenName, amount) => {
            // 准备
            let beforeData = await checkBefore(tokenName);
            // mint
            await mintCoin(tokenName, amount);
            // 校验
            await checkBalance(tokenName, amount, beforeData);
        }

        let checkMintCoinWidthPromise = async (tokenName, amount) => {
            // 准备
            let beforeData = await checkBefore(tokenName);
            // 获取签名
            let d = deadline();
            let sign = await getSignMessage(getCoin[tokenName + '_ADDRESS'], getCoin[tokenName + '_ABI'], buyerAddress, greatLottoCoin.address, parseUnits(amount + '', getCoin[tokenName + '_DECIMALS']), d);
            // mint
            await partnerTest.coinMint(getCoin[tokenName + '_ADDRESS'], amount, buyerAddress, d, sign.v, sign.r, sign.s)
            // 校验
            await checkBalance(tokenName, amount, beforeData);
        }

        let checkBalance = async (tokenName, amount, beforeData) => {
            // 校验
            expect(await getCoin['get' + tokenName + 'Balance'](greatLottoCoin.address)).to.equal(beforeData.coinBalance + ethers.parseUnits(amount + '', getCoin[tokenName + '_DECIMALS']));
            expect(await greatLottoCoin.balanceOf(buyerAddress)).to.equal(beforeData.buyerBalance + parseEther(amount + ''));
        }
       
        it("Should mint", async function() {
            await checkMintCoin('USDT', 1000);
            await checkMintCoin('USDC', 1000);
            await checkMintCoin('DAI', 1000);
        });

        it("Should mint with promise", async function() {
            await checkMintCoinWidthPromise('DAI', 1000);
            await checkMintCoinWidthPromise('USDC', 1000);
        });
        
    })

    // 测试转账
    describe("transfer", function() {

        beforeEach(async () => {
            // 充值
            await greatLottoCoin.mintFor(buyerAddress, parseEther('1000'));
        });

        // 校验前准备
        let checkBalanceBefore = async (amountSmall) => {
            let amount = ethers.parseUnits(amountSmall + '', decimalsLocalCoin);
            let senderBalanceBefore = await greatLottoCoin.balanceOf(buyerAddress);
            let receiverBalanceBefore = await greatLottoCoin.balanceOf(ownerAddress);
            return [amount, senderBalanceBefore, receiverBalanceBefore];
        };

        // 校验
        let checkBalanceAfter = async (amount, senderBalanceBefore, receiverBalanceBefore) => {
            expect(await greatLottoCoin.balanceOf(buyerAddress)).to.equal(senderBalanceBefore - amount);
            expect(await greatLottoCoin.balanceOf(ownerAddress)).to.equal(receiverBalanceBefore + amount);
        };

        // 直接转账
        it("Should transfer directly", async function() {
            let buyerCoinContract = await greatLottoCoin.connect(await ethers.getImpersonatedSigner(buyerAddress));
            // 准备
            let [amount, senderBalanceBefore, receiverBalanceBefore] = await checkBalanceBefore(100);
            // 转账
            await expect(buyerCoinContract.transfer(ownerAddress, amount)).to.emit(buyerCoinContract, 'Transfer').withArgs(buyerAddress, ownerAddress, amount);
            // 校验
            await checkBalanceAfter(amount, senderBalanceBefore, receiverBalanceBefore);

        });

        // 授权转账
        it("Should transfer with approve", async function() {
            let buyerCoinContract = await greatLottoCoin.connect(await ethers.getImpersonatedSigner(buyerAddress));           
            // 准备
            let [amount, senderBalanceBefore, receiverBalanceBefore] = await checkBalanceBefore(100);
            // 授权
            await expect(buyerCoinContract.approve(ownerAddress, amount)).to.emit(buyerCoinContract, 'Approval').withArgs(buyerAddress, ownerAddress, amount);
            // 转账
            await expect(greatLottoCoin.transferFrom(buyerAddress, ownerAddress, amount)).to.emit(greatLottoCoin, 'Transfer').withArgs(buyerAddress, ownerAddress, amount);
            // 校验
            await checkBalanceAfter(amount, senderBalanceBefore, receiverBalanceBefore);
        });

        // 签名转账
        it("Should transfer with sign", async function() {
            // 准备
            let [amount, senderBalanceBefore, receiverBalanceBefore] = await checkBalanceBefore(100);
            // 获取签名
            let d = deadline();
            let sign = await getSignMessageByCoin(greatLottoCoin, buyerAddress, ownerAddress, amount, d);
            // 签名
            await greatLottoCoin.permit(buyerAddress, ownerAddress, amount, d, sign.v, sign.r, sign.s);
            // 转账
            await expect(greatLottoCoin.transferFrom(buyerAddress, ownerAddress, amount)).to.emit(greatLottoCoin, 'Transfer').withArgs(buyerAddress, ownerAddress, amount);
            // 校验
            await checkBalanceAfter(amount, senderBalanceBefore, receiverBalanceBefore);
        });

    });

    // 测试提款
    describe("withdraw", function() {

        let buyerCoinContract;

        beforeEach(async () => {
            buyerCoinContract = await greatLottoCoin.connect(await ethers.getImpersonatedSigner(buyerAddress));
            await mintCoin('USDT', 1000);
            await mintCoin('USDC', 1000);
            await mintCoin('DAI', 1000);
        });

        // 金额足够的提款
        let withdrawByEnoughBalance = async (tokenName, amount) => {
            // 提款前余额
            let balanceBefore = await getCoin['get' + tokenName + 'Balance'](greatLottoCoin.address);
            let buyerBalanceBefore = await getCoin['get' + tokenName + 'Balance'](buyerAddress);
            let amountBig = ethers.parseUnits(amount + '', getCoin[tokenName + '_DECIMALS']);
            // 提款
            await expect(buyerCoinContract.withdraw(getCoin[tokenName + '_ADDRESS'], amount)).to.emit(buyerCoinContract, 'GreatLottoCoinBaseWithdrawn').withArgs(buyerAddress, ethers.getAddress(getCoin[tokenName + '_ADDRESS']), amountBig);
            // 提款后余额
            expect(await getCoin['get' + tokenName + 'Balance'](greatLottoCoin.address)).to.equal(balanceBefore - amountBig);
            expect(await getCoin['get' + tokenName + 'Balance'](buyerAddress)).to.equal(buyerBalanceBefore + amountBig);
        };

        // 金额不足的提款会失败 
        let withdrawByNotEnoughBalance = async (tokenName, amount) => {
            // 提款前余额
            let balanceBefore = await getCoin['get' + tokenName + 'Balance'](greatLottoCoin.address);
            let amountBig = ethers.parseUnits(amount + '', getCoin[tokenName + '_DECIMALS']);
            // 提款
            await expect(buyerCoinContract.withdraw(getCoin[tokenName + '_ADDRESS'], amount)).to.be.revertedWithCustomError(buyerCoinContract, "ErrorInsufficientBalance").withArgs(ethers.getAddress(getCoin[tokenName + '_ADDRESS']), greatLottoCoin.address, balanceBefore, amountBig);
        };

        // 如果货币地址不支持，则应该revert
        it("Should revert if currency address not support", async function() {
            // TUSD
            const elseToken = '0x0000000000085d4780B73119b644AE5ecd22b376';
            await expect(buyerCoinContract.withdraw(elseToken, 100)).to.be.revertedWithCustomError(buyerCoinContract, "ErrorUnsupportedToken").withArgs(elseToken);
        });

        // 提款金额不足，应该revert
        it("Should revert if amount not enough", async function() {
            await greatLottoCoin.burnFrom(buyerAddress, ethers.parseEther('2500'));

            await expect(buyerCoinContract.withdraw(getCoin.USDT_ADDRESS, 600)).to.be.revertedWithCustomError(buyerCoinContract, "ERC20InsufficientBalance").withArgs(buyerAddress, await greatLottoCoin.balanceOf(buyerAddress), ethers.parseEther('600'));
        });

        // 相应币种提款金额足够，提款成功
        it("Should withdraw current Coin with enough balance", async function() {
            // 提款
            await withdrawByEnoughBalance('USDT', 100);
            await withdrawByEnoughBalance('USDC', 100);
            await withdrawByEnoughBalance('DAI', 100);
        });

        it("Should revert if base coin amount not enough", async function() {
            // 充值
            await greatLottoCoin.mintFor(buyerAddress, parseEther('10000'));
            // 提款
            await withdrawByNotEnoughBalance('USDT', 5000);
            await withdrawByNotEnoughBalance('USDC', 5000);
            await withdrawByNotEnoughBalance('DAI', 5000);
        });

    });

    // 测试recover
    describe("recover", function() {

        beforeEach(async () => {
            await mintCoin('USDT', 1000);
            await mintCoin('USDC', 1000);
            await mintCoin('DAI', 1000);
        });

        // 奖池余额校验
        it("Should check totalSupply", async function() {

            let amountLocalCoin = ethers.parseUnits('3000', decimalsLocalCoin);
            //console.log('amountLocalCoin: '+ amountLocalCoin);
            // 总发行量
            expect(await greatLottoCoin.totalSupply()).to.equal(amountLocalCoin);

            // 无需 recover
            await expect(greatLottoCoin.recover()).to.be.revertedWithCustomError(greatLottoCoin, "GreatLottoCoinBaseNoNeedRecover").withArgs(amountLocalCoin, await greatLottoCoin.totalSupply());
        
        });

        it("Should recover", async function() {

            // 保存总发行
            let totalSupplyBalance = await greatLottoCoin.totalSupply();
            let gap = ethers.parseUnits('100', decimalsLocalCoin);

            let ownerBalanceBefore = await greatLottoCoin.balanceOf(ownerAddress);

            // 销毁金额
            await greatLottoCoin.burnFrom(buyerAddress, gap);

            // 检测总发行量
            expect(await greatLottoCoin.totalSupply()).to.equal(totalSupplyBalance - gap);

            // 执行recover
            await expect(greatLottoCoin.recover()).to.emit(greatLottoCoin, 'GreatLottoCoinBaseRecovered').withArgs(gap, totalSupplyBalance);
            
            // 检测总发行量
            expect(await greatLottoCoin.totalSupply()).to.equal(totalSupplyBalance);

            // 检测owner余额
            expect(await greatLottoCoin.balanceOf(ownerAddress)).to.equal(ownerBalanceBefore + gap);


        });

    });



    
});
