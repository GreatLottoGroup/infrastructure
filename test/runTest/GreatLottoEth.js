const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deploy } = require('../utils/deployTool');
const getCoin = require('../utils/getCoin');
const { getSignMessageByCoin } = require('../utils/permitUtils');

const { parseEther, provider } = ethers;

// GreatLotto Eth  集成测试
describe("GreatLottoEth", function() {

    // owner
    const ownerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    // 买家账户
    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

    const InitializeFixture = async () => {
       
        // 合约部署
        let contractList = await deploy();
    
        // 充值 100 WETH
        await getCoin.getWETHCoin(buyerAddress, 100);

        // 重置时间戳
        await setTimeGap();
     
        return contractList;

    }

    let greatLottoEth;

    let timeGap = 0;

    async function setTimeGap() {
        timeGap =  await time.latest() - getNow();
        console.log('timeGap: '+ timeGap);
    };
    function deadline(){
        return getNow() + timeGap + 10;
    };
    function getNow(){
        return parseInt(new Date().getTime()/1000);
    };

    beforeEach(async () => {
        ({ greatLottoEth, partnerTest } = await loadFixture(InitializeFixture));
    });

    let mintCoin = async (tokenName, amount) => {
        const amountEth = parseEther(amount + '');
        // 授权
        await getCoin['approve' + tokenName + 'Coin'](buyerAddress, greatLottoEth.address, amount);
        // mint
        await partnerTest.ethCoinMint(getCoin[tokenName + '_ADDRESS'], amountEth, buyerAddress)
    }

    // 测试Mint
    describe("mint", function() {

        it("Should mint", async function() {
            // 准备
            const coinBalance = await getCoin.getWETHBalance(greatLottoEth.address);
            const buyerBalance = await greatLottoEth.balanceOf(buyerAddress);
            // mint
            await mintCoin('WETH', 10);
            // 校验
            expect(await getCoin.getWETHBalance(greatLottoEth.address)).to.equal(coinBalance + parseEther('10'));
            expect(await greatLottoEth.balanceOf(buyerAddress)).to.equal(buyerBalance + parseEther('10'));
        });
        
    })

    // 测试转账
    describe("transfer", function() {

        beforeEach(async () => {
            // 充值
            await greatLottoEth.mintFor(buyerAddress, parseEther('1000'));
        });

        // 校验前准备
        let checkBalanceBefore = async (amountSmall) => {
            let amount = parseEther(amountSmall + '');
            let senderBalanceBefore = await greatLottoEth.balanceOf(buyerAddress);
            let receiverBalanceBefore = await greatLottoEth.balanceOf(ownerAddress);
            return [amount, senderBalanceBefore, receiverBalanceBefore];
        };

        // 校验
        let checkBalanceAfter = async (amount, senderBalanceBefore, receiverBalanceBefore) => {
            expect(await greatLottoEth.balanceOf(buyerAddress)).to.equal(senderBalanceBefore - amount);
            expect(await greatLottoEth.balanceOf(ownerAddress)).to.equal(receiverBalanceBefore + amount);
        };

        // 直接转账
        it("Should transfer directly", async function() {
            let buyerCoinContract = await greatLottoEth.connect(await ethers.getImpersonatedSigner(buyerAddress));
            // 准备
            let [amount, senderBalanceBefore, receiverBalanceBefore] = await checkBalanceBefore(100);
            // 转账
            await expect(buyerCoinContract.transfer(ownerAddress, amount)).to.emit(greatLottoEth, 'Transfer').withArgs(buyerAddress, ownerAddress, amount);
            // 校验
            await checkBalanceAfter(amount, senderBalanceBefore, receiverBalanceBefore);

        });

        // 授权转账
        it("Should transfer with approve", async function() {
            let buyerCoinContract = await greatLottoEth.connect(await ethers.getImpersonatedSigner(buyerAddress));           
            // 准备
            let [amount, senderBalanceBefore, receiverBalanceBefore] = await checkBalanceBefore(100);
            // 授权
            await expect(buyerCoinContract.approve(ownerAddress, amount)).to.emit(greatLottoEth, 'Approval').withArgs(buyerAddress, ownerAddress, amount);
            // 转账
            await expect(greatLottoEth.transferFrom(buyerAddress, ownerAddress, amount)).to.emit(greatLottoEth, 'Transfer').withArgs(buyerAddress, ownerAddress, amount);
            // 校验
            await checkBalanceAfter(amount, senderBalanceBefore, receiverBalanceBefore);
        });

        // 签名转账
        it("Should transfer with sign", async function() {
            // 准备
            let [amount, senderBalanceBefore, receiverBalanceBefore] = await checkBalanceBefore(100);
            // 获取签名
            let d = deadline();
            let sign = await getSignMessageByCoin(greatLottoEth, buyerAddress, ownerAddress, amount, d);
            // 签名
            await greatLottoEth.permit(buyerAddress, ownerAddress, amount, d, sign.v, sign.r, sign.s);
            // 转账
            await expect(greatLottoEth.transferFrom(buyerAddress, ownerAddress, amount)).to.emit(greatLottoEth, 'Transfer').withArgs(buyerAddress, ownerAddress, amount);
            // 校验
            await checkBalanceAfter(amount, senderBalanceBefore, receiverBalanceBefore);
        });

    });

    // 测试存款 by eth
    describe("wrap", function() {

        let buyerCoinContract;

        beforeEach(async () => {
            buyerCoinContract = await greatLottoEth.connect(await ethers.getImpersonatedSigner(buyerAddress));
        });
       
        it("Should revert if no eth send", async function() {
            await expect(buyerCoinContract.wrap()).to.be.revertedWithCustomError(greatLottoEth, "ErrorInvalidAmount").withArgs(0);
        });

        it("Should success wrap", async function() {
            let amount = parseEther('10');
            let ethBalanceBefore = await provider.getBalance(buyerAddress);
            let greatEthBalanceBefore = await greatLottoEth.balanceOf(buyerAddress);
            let greatEthBefore = await provider.getBalance(greatLottoEth.address);

            await expect(buyerCoinContract.wrap({value: amount})).to.emit(greatLottoEth, 'GreatLottoEthWrapped').withArgs(buyerAddress, amount);

            expect(await provider.getBalance(buyerAddress)).to.below(ethBalanceBefore - amount);
            expect(await greatLottoEth.balanceOf(buyerAddress)).to.equal(greatEthBalanceBefore + amount);
            expect(await provider.getBalance(greatLottoEth.address)).to.equal(greatEthBefore + amount);

        });

    });

    // 测试提款
    describe("unwrap", function() {
        let buyerCoinContract;

        beforeEach(async () => {
            buyerCoinContract = await greatLottoEth.connect(await ethers.getImpersonatedSigner(buyerAddress));
        });


        // 如果基础货币金额不足，则应该revert
        it("Should revert if eth not enough", async function() {
            await expect(buyerCoinContract.unwrap(parseEther('10'))).to.be.revertedWithCustomError(greatLottoEth, "ErrorInsufficientBalanceEth").withArgs(greatLottoEth.address, await provider.getBalance(greatLottoEth.address), parseEther('10'));
        });

        // 用户余额不足，应该revert
        it("Should revert if balance not enough", async function() {
            let amount = parseEther('10');
            // 充值
            await buyerCoinContract.wrap({value: amount});
            await greatLottoEth.burnFrom(buyerAddress, amount);

            await expect(buyerCoinContract.unwrap(parseEther('10'))).to.be.revertedWithCustomError(greatLottoEth, "ERC20InsufficientBalance").withArgs(buyerAddress, await greatLottoEth.balanceOf(buyerAddress), parseEther('10'));
        });

        // 成功提现
        it("Should success to withdraw", async function() {
            let amount = parseEther('10');
            // 充值
            await buyerCoinContract.wrap({value: amount});
            
            let ethBalanceBefore = await provider.getBalance(buyerAddress);
            let greatEthBalanceBefore = await greatLottoEth.balanceOf(buyerAddress);
            let greatEthBefore = await provider.getBalance(greatLottoEth.address);
            // 提款
            await expect(buyerCoinContract.unwrap(amount)).to.emit(greatLottoEth, 'GreatLottoEthUnwrapped').withArgs(buyerAddress, amount);
            // 提款后余额
            expect(await provider.getBalance(buyerAddress)).to.below(ethBalanceBefore + amount);
            expect(await greatLottoEth.balanceOf(buyerAddress)).to.equal(greatEthBalanceBefore - amount);
            expect(await provider.getBalance(greatLottoEth.address)).to.equal(greatEthBefore - amount);
        });


    });

    // 测试提款
    describe("withdraw By WETH", function() {

        let buyerCoinContract;

        beforeEach(async () => {
            buyerCoinContract = await greatLottoEth.connect(await ethers.getImpersonatedSigner(buyerAddress));
            await mintCoin('WETH', 10);
        });

        // 如果货币地址不支持，则应该revert
        it("Should revert if currency address not support", async function() {
            // TUSD
            const elseToken = '0x0000000000085d4780B73119b644AE5ecd22b376';
            await expect(buyerCoinContract.withdraw(elseToken, 100)).to.be.revertedWithCustomError(greatLottoEth, "ErrorUnsupportedToken").withArgs(elseToken);
        });

        // base coin金额不足，应该revert
        it("Should revert if base coin not enough", async function() {
            let amount = parseEther('100');

            await greatLottoEth.mintFor(buyerAddress, amount);

            await expect(buyerCoinContract.withdraw(getCoin.WETH_ADDRESS, amount)).to.be.revertedWithCustomError(greatLottoEth, "ErrorInsufficientBalance").withArgs(getCoin.WETH_ADDRESS, greatLottoEth.address, await getCoin.getWETHBalance(greatLottoEth.address), amount);
        });

        // 用户余额不足，应该revert
        it("Should revert if balance not enough", async function() {
            let amount = parseEther('6');
            await greatLottoEth.burnFrom(buyerAddress, ethers.parseEther('5'));

            await expect(buyerCoinContract.withdraw(getCoin.WETH_ADDRESS, amount)).to.be.revertedWithCustomError(greatLottoEth, "ERC20InsufficientBalance").withArgs(buyerAddress, await greatLottoEth.balanceOf(buyerAddress), amount);
        });

        // 相应币种提款金额足够，提款成功
        it("Should success to withdraw ", async function() {
            let amount = parseEther('1');

            // 提款前余额
            let balanceBefore = await getCoin.getWETHBalance(greatLottoEth.address);
            let buyerBalanceBefore = await getCoin.getWETHBalance(buyerAddress);
            let greatBalanceBefore = await greatLottoEth.balanceOf(buyerAddress);
            // 提款
            await expect(buyerCoinContract.withdraw(getCoin.WETH_ADDRESS, amount)).to.emit(greatLottoEth, 'GreatLottoCoinBaseWithdrawn').withArgs(buyerAddress, getCoin.WETH_ADDRESS, amount);
            // 提款后余额
            expect(await getCoin.getWETHBalance(greatLottoEth.address)).to.equal(balanceBefore - amount);
            expect(await getCoin.getWETHBalance(buyerAddress)).to.equal(buyerBalanceBefore + amount);
            expect(await greatLottoEth.balanceOf(buyerAddress)).to.equal(greatBalanceBefore - amount);
        });

    });

    // 测试recover
    describe("recover", function() {

        let buyerCoinContract;

        beforeEach(async () => {
            buyerCoinContract = await greatLottoEth.connect(await ethers.getImpersonatedSigner(buyerAddress));
            await mintCoin('WETH', 10);
            await buyerCoinContract.wrap({value: parseEther('10')});
        });

        // 奖池余额校验`
        it("Should check totalSupply & no need recover", async function() {

            // 总发行量
            expect(await greatLottoEth.totalSupply()).to.equal(parseEther('20'));

            // 无需 recover
            await expect(greatLottoEth.recover()).to.be.revertedWithCustomError(greatLottoEth, "GreatLottoCoinBaseNoNeedRecover").withArgs(parseEther('20'), await greatLottoEth.totalSupply());
        
        });

        it("Should recover", async function() {

            let amount = parseEther('20');
            let gap = parseEther('1')
            let ownerBalanceBefore = await greatLottoEth.balanceOf(ownerAddress);

            await greatLottoEth.burnFrom(buyerAddress, gap);

            // 检测总发行量
            expect(await greatLottoEth.totalSupply()).to.equal(amount - gap);

            // 执行recover
            await expect(greatLottoEth.recover()).to.emit(greatLottoEth, 'GreatLottoCoinBaseRecovered').withArgs(gap, amount);
            
            // 检测总发行量
            expect(await greatLottoEth.totalSupply()).to.equal(amount);

            // 检测owner余额
            expect(await greatLottoEth.balanceOf(ownerAddress)).to.equal(ownerBalanceBefore + gap);

        });

    });



    
});
