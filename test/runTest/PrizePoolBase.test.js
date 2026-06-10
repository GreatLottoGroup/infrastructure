const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { deployPrizePoolBaseFixture } = require('../utils/deployPrizePoolBaseFixture');
const getCoin = require('../utils/getCoin');
const { getSignMessageByCoin, getSignMessage } = require('../utils/permitUtils');
const { getDaoShares } = require('../utils/newConvert');

const { parseEther, parseUnits, ZeroAddress, ZeroHash } = ethers;

describe("PrizePoolBase", function () {

    const ownerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
    const recipientAddress = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';
    const channelOwnerAddress = '0x90F79bf6EB2c4f870365E785982E1f101E93b906';

    let timeGap = 0;
    async function setTimeGap() {
        timeGap = await time.latest() - getNow();
    }
    function deadline() {
        return getNow() + timeGap + 1200;
    }
    function getNow() {
        return parseInt(new Date().getTime() / 1000);
    }

    const InitFixture = async () => {
        const ctx = await deployPrizePoolBaseFixture();
        await setTimeGap();
        return ctx;
    };

    const InitFixtureZeroRates = async () => {
        // 构造期 rate==0 是允许的（仅 setter 拒绝 0）
        const ctx = await deployPrizePoolBaseFixture({ channelRate: 0, sellRate: 0 });
        await setTimeGap();
        return ctx;
    };

    let greatLottoCoin, daoCoin, daoBenefitPool, salesChannel, harness;

    beforeEach(async () => {
        ({ greatLottoCoin, daoCoin, daoBenefitPool, salesChannel, harness } = await loadFixture(InitFixture));
    });

    // 注册有效渠道（owner 为渠道 owner）
    async function registerActiveChannel(channel = salesChannel, signerAddr = channelOwnerAddress, name = "test-chn") {
        const signer = await ethers.getImpersonatedSigner(signerAddr);
        // 给签名账号一些 ETH（可能没有）
        await ethers.provider.send("hardhat_setBalance", [signerAddr, "0x1000000000000000000"]);
        let chnId;
        const tx = await channel.connect(signer).registerChannel(name, deadline());
        const receipt = await tx.wait();
        for (const log of receipt.logs) {
            try {
                const parsed = channel.interface.parseLog(log);
                if (parsed && parsed.name === 'SalesChannelRegistered') {
                    chnId = parsed.args[1];
                    break;
                }
            } catch (e) { /* skip */ }
        }
        return { chnId, signerAddr };
    }

    // --- Section 5.4: deployment assertions ---
    describe("deployment", function () {
        it("immutable getters & default rates", async function () {
            expect(await harness.GreatLottoCoinAddress()).to.equal(greatLottoCoin.address);
            expect(await harness.DaoCoinAddress()).to.equal(daoCoin.address);
            expect(await harness.DaoBenefitPoolAddress()).to.equal(daoBenefitPool.address);
            expect(await harness.SalesChannelAddress()).to.equal(salesChannel.address);
            expect(await harness.channelBenefitRate()).to.equal(30);
            expect(await harness.sellBenefitRate()).to.equal(70);
        });

        it("getCoin returns ICoinBase whose address is GLC", async function () {
            expect(await harness.getCoin()).to.equal(greatLottoCoin.address);
        });
    });

    // --- Section 6: _colletWithCoin (direct) ---
    describe("_colletWithCoin (direct)", function () {
        const FN = 'colletWithCoin(address,address,uint256)';

        it("6.1 amount==0 reverts ErrorInvalidAmount(0)", async function () {
            await expect(harness[FN](greatLottoCoin.address, ownerAddress, 0))
                .to.be.revertedWithCustomError(harness, "ErrorInvalidAmount").withArgs(0);
        });

        it("6.2 GLC path: approve then collect, harness GLC balance increases", async function () {
            const amount = 1000n; // 1000 (will be scaled by getAmount → *1e18)
            // 给 buyer 铸造 GLC
            await greatLottoCoin.mintFor(buyerAddress, parseEther('1000'));
            // approve harness
            const buyerSigner = await ethers.getImpersonatedSigner(buyerAddress);
            await ethers.provider.send("hardhat_setBalance", [buyerAddress, "0x1000000000000000000"]);
            await greatLottoCoin.connect(buyerSigner).approve(harness.address, parseEther('1000'));

            const balBefore = await greatLottoCoin.balanceOf(harness.address);
            await harness[FN](greatLottoCoin.address, buyerAddress, amount);
            const balAfter = await greatLottoCoin.balanceOf(harness.address);
            expect(balAfter - balBefore).to.equal(parseEther('1000'));
        });

        it("6.3 外币 mint path: USDC approve GLC, harness GLC balance increases", async function () {
            const amount = 100;
            await getCoin.getUSDCCoin(buyerAddress, amount);
            // GLC._depositFor 内做 safeTransferFrom(payer, GLC, ...)，所以 buyer 要 approve GLC
            await getCoin.approveUSDCCoin(buyerAddress, greatLottoCoin.address, amount);
            const balBefore = await greatLottoCoin.balanceOf(harness.address);
            await harness[FN](getCoin.USDC_ADDRESS, buyerAddress, amount);
            const balAfter = await greatLottoCoin.balanceOf(harness.address);
            expect(balAfter - balBefore).to.equal(parseEther(amount + ''));
        });

        it("6.4 GLC path without approve reverts ERC20InsufficientAllowance", async function () {
            await greatLottoCoin.mintFor(buyerAddress, parseEther('1000'));
            // 不 approve
            await expect(harness[FN](greatLottoCoin.address, buyerAddress, 1000n))
                .to.be.revertedWithCustomError(greatLottoCoin, "ERC20InsufficientAllowance");
        });
    });

    // --- Section 7: _colletWithCoin (permit) ---
    describe("_colletWithCoin (permit)", function () {
        const FN = 'colletWithCoin(address,address,uint256,uint256,uint8,bytes32,bytes32)';

        it("7.1 amount==0 reverts ErrorInvalidAmount(0)", async function () {
            await expect(harness[FN](greatLottoCoin.address, ownerAddress, 0, deadline(), 0, ZeroHash, ZeroHash))
                .to.be.revertedWithCustomError(harness, "ErrorInvalidAmount").withArgs(0);
        });

        it("7.2 GLC permit path — allowance 不足时调用 permit + transferFrom", async function () {
            const amount = 1000;
            await greatLottoCoin.mintFor(buyerAddress, parseEther(amount + ''));
            await ethers.provider.send("hardhat_setBalance", [buyerAddress, "0x1000000000000000000"]);

            const d = deadline();
            const sign = await getSignMessageByCoin(
                greatLottoCoin,
                buyerAddress,
                harness.address,
                parseEther(amount + ''),
                d
            );

            const balBefore = await greatLottoCoin.balanceOf(harness.address);
            const nonceBefore = await greatLottoCoin.nonces(buyerAddress);
            await harness[FN](greatLottoCoin.address, buyerAddress, amount, d, sign.v, sign.r, sign.s);
            const balAfter = await greatLottoCoin.balanceOf(harness.address);
            const nonceAfter = await greatLottoCoin.nonces(buyerAddress);

            expect(balAfter - balBefore).to.equal(parseEther(amount + ''));
            expect(nonceAfter - nonceBefore).to.equal(1n);
        });

        it("7.3 GLC permit path — allowance 已足够时跳过 permit", async function () {
            const amount = 500;
            await greatLottoCoin.mintFor(buyerAddress, parseEther(amount + ''));
            const buyerSigner = await ethers.getImpersonatedSigner(buyerAddress);
            await ethers.provider.send("hardhat_setBalance", [buyerAddress, "0x1000000000000000000"]);
            await greatLottoCoin.connect(buyerSigner).approve(harness.address, parseEther(amount + ''));

            const nonceBefore = await greatLottoCoin.nonces(buyerAddress);
            // 传 0 签名也不会被使用
            await harness[FN](greatLottoCoin.address, buyerAddress, amount, deadline(), 0, ZeroHash, ZeroHash);
            const nonceAfter = await greatLottoCoin.nonces(buyerAddress);
            // permit 未被调用 → nonce 不变
            expect(nonceAfter).to.equal(nonceBefore);
        });

        it("7.4 外币 permit mint path: USDC permit", async function () {
            const amount = 100;
            await getCoin.getUSDCCoin(buyerAddress, amount);

            const d = deadline();
            const sign = await getSignMessage(
                getCoin.USDC_ADDRESS,
                getCoin.USDC_ABI,
                buyerAddress,
                greatLottoCoin.address,
                parseUnits(amount + '', getCoin.USDC_DECIMALS),
                d
            );

            const balBefore = await greatLottoCoin.balanceOf(harness.address);
            await harness[FN](getCoin.USDC_ADDRESS, buyerAddress, amount, d, sign.v, sign.r, sign.s);
            const balAfter = await greatLottoCoin.balanceOf(harness.address);
            expect(balAfter - balBefore).to.equal(parseEther(amount + ''));
        });
    });

    // --- Section 8: _transferTo ---
    describe("_transferTo", function () {
        it("8.1 amount==0 早退（不 revert，余额为 0 也能调用）", async function () {
            const balBefore = await greatLottoCoin.balanceOf(recipientAddress);
            await expect(harness.transferTo(greatLottoCoin.address, recipientAddress, 0)).not.to.be.reverted;
            expect(await greatLottoCoin.balanceOf(recipientAddress)).to.equal(balBefore);
        });

        it("8.2 余额不足 revert ErrorInsufficientBalance", async function () {
            const amount = parseEther('100');
            await expect(harness.transferTo(greatLottoCoin.address, recipientAddress, amount))
                .to.be.revertedWithCustomError(harness, "ErrorInsufficientBalance")
                .withArgs(greatLottoCoin.address, harness.address, 0n, amount);
        });

        it("8.3 正常 transfer: recipient +amount, harness -amount", async function () {
            const amount = parseEther('500');
            await greatLottoCoin.mintFor(harness.address, parseEther('1000'));
            const recipBefore = await greatLottoCoin.balanceOf(recipientAddress);
            const harnessBefore = await greatLottoCoin.balanceOf(harness.address);
            await harness.transferTo(greatLottoCoin.address, recipientAddress, amount);
            expect(await greatLottoCoin.balanceOf(recipientAddress) - recipBefore).to.equal(amount);
            expect(harnessBefore - await greatLottoCoin.balanceOf(harness.address)).to.equal(amount);
        });

        it("8.4 silent-fail mock revert ErrorPaymentUnsuccessful", async function () {
            const Mock = await ethers.getContractFactory("MockSilentFailCoin");
            const silent = await Mock.deploy();
            await silent.waitForDeployment();
            silent.address = await silent.getAddress();
            // 给 harness 一些余额（但 transfer 不会真扣）
            await silent.mintFor(harness.address, 1000n);
            await expect(harness.transferTo(silent.address, recipientAddress, 500n))
                .to.be.revertedWithCustomError(harness, "ErrorPaymentUnsuccessful");
        });

        it("8.5 fee-on-transfer mock revert ErrorPaymentUnsuccessful", async function () {
            const Mock = await ethers.getContractFactory("MockFeeOnTransferCoin");
            const fee = await Mock.deploy();
            await fee.waitForDeployment();
            fee.address = await fee.getAddress();
            await fee.mintFor(harness.address, 1000n);
            await expect(harness.transferTo(fee.address, recipientAddress, 500n))
                .to.be.revertedWithCustomError(harness, "ErrorPaymentUnsuccessful");
        });
    });

    // --- Section 9: _channelBenefitTransfer ---
    describe("_channelBenefitTransfer", function () {
        it("9.1 invalid channel (id 不存在) reverts SalesChannelInvalid(address(0))", async function () {
            await greatLottoCoin.mintFor(harness.address, parseEther('1000'));
            await expect(harness.channelBenefitTransfer(greatLottoCoin.address, parseEther('100'), 9999))
                .to.be.revertedWithCustomError(salesChannel, "SalesChannelInvalid").withArgs(ZeroAddress);
        });

        it("9.2 valid channel: channel +benefit, harness -benefit", async function () {
            const { chnId, signerAddr } = await registerActiveChannel();
            const benefit = parseEther('100');
            await greatLottoCoin.mintFor(harness.address, parseEther('1000'));
            const chnBefore = await greatLottoCoin.balanceOf(signerAddr);
            const hBefore = await greatLottoCoin.balanceOf(harness.address);
            await harness.channelBenefitTransfer(greatLottoCoin.address, benefit, chnId);
            expect(await greatLottoCoin.balanceOf(signerAddr) - chnBefore).to.equal(benefit);
            expect(hBefore - await greatLottoCoin.balanceOf(harness.address)).to.equal(benefit);
        });
    });

    // --- Section 10: _daoBenefitTransfer / _getBenefitByRate / _mintDaoCoinToPayer ---
    describe("dao + rate + mintDao helpers", function () {
        it("10.1 _daoBenefitTransfer: DAO pool +benefit", async function () {
            const benefit = parseEther('250');
            await greatLottoCoin.mintFor(harness.address, parseEther('1000'));
            const daoBefore = await greatLottoCoin.balanceOf(daoBenefitPool.address);
            await harness.daoBenefitTransfer(greatLottoCoin.address, benefit);
            expect(await greatLottoCoin.balanceOf(daoBenefitPool.address) - daoBefore).to.equal(benefit);
        });

        it("10.2 _getBenefitByRate(1000, 70) = (70, 930)", async function () {
            const r = await harness.getBenefitByRate(1000, 70);
            expect(r[0]).to.equal(70n);
            expect(r[1]).to.equal(930n);
        });

        it("10.3 _getBenefitByRate(1000, 0) = (0, 1000)", async function () {
            const r = await harness.getBenefitByRate(1000, 0);
            expect(r[0]).to.equal(0n);
            expect(r[1]).to.equal(1000n);
        });

        it("10.4 _getBenefitByRate(1000, 1000) = (1000, 0)", async function () {
            const r = await harness.getBenefitByRate(1000, 1000);
            expect(r[0]).to.equal(1000n);
            expect(r[1]).to.equal(0n);
        });

        it("10.5 _mintDaoCoinToPayer triggers DaoCoin.mintToUser", async function () {
            const before = await daoCoin.balanceOf(buyerAddress);
            await harness.mintDaoCoinToPayer(buyerAddress, parseEther('1000'));
            const after = await daoCoin.balanceOf(buyerAddress);
            expect(after - before).to.equal(getDaoShares(parseEther('1000')));
        });
    });

    // --- Section 11: setChannelBenefitRate / setSellBenefitRate ---
    describe("rate setters", function () {
        const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;

        it("11.1 setChannelBenefitRate: non-admin reverts AccessControlUnauthorizedAccount", async function () {
            const buyerSigner = await ethers.getImpersonatedSigner(buyerAddress);
            await ethers.provider.send("hardhat_setBalance", [buyerAddress, "0x1000000000000000000"]);
            await expect(harness.connect(buyerSigner).setChannelBenefitRate(40))
                .to.be.revertedWithCustomError(harness, "AccessControlUnauthorizedAccount")
                .withArgs(buyerAddress, DEFAULT_ADMIN_ROLE);
        });

        it("11.2 setChannelBenefitRate(0) reverts ErrorInvalidAmount(0)", async function () {
            await expect(harness.setChannelBenefitRate(0))
                .to.be.revertedWithCustomError(harness, "ErrorInvalidAmount").withArgs(0);
        });

        it("11.3 setChannelBenefitRate(40) updates + emits + returns true", async function () {
            await expect(harness.setChannelBenefitRate(40))
                .to.emit(harness, "ChannelBenefitRateChanged").withArgs(40);
            expect(await harness.channelBenefitRate()).to.equal(40);
            expect(await harness.setChannelBenefitRate.staticCall(50)).to.equal(true);
        });

        it("11.4 setSellBenefitRate: non-admin reverts AccessControlUnauthorizedAccount", async function () {
            const buyerSigner = await ethers.getImpersonatedSigner(buyerAddress);
            await ethers.provider.send("hardhat_setBalance", [buyerAddress, "0x1000000000000000000"]);
            await expect(harness.connect(buyerSigner).setSellBenefitRate(80))
                .to.be.revertedWithCustomError(harness, "AccessControlUnauthorizedAccount")
                .withArgs(buyerAddress, DEFAULT_ADMIN_ROLE);
        });

        it("11.5 setSellBenefitRate(0) reverts ErrorInvalidAmount(0)", async function () {
            await expect(harness.setSellBenefitRate(0))
                .to.be.revertedWithCustomError(harness, "ErrorInvalidAmount").withArgs(0);
        });

        it("11.6 setSellBenefitRate(80) updates + emits + returns true", async function () {
            await expect(harness.setSellBenefitRate(80))
                .to.emit(harness, "SellBenefitRateChanged").withArgs(80);
            expect(await harness.sellBenefitRate()).to.equal(80);
            expect(await harness.setSellBenefitRate.staticCall(90)).to.equal(true);
        });

        it("11.7 ABI surface: no historical changeBenefitRate / BenefitRateChanged", async function () {
            const fns = harness.interface.fragments.filter(f => f.type === 'function').map(f => f.name);
            const evts = harness.interface.fragments.filter(f => f.type === 'event').map(f => f.name);
            expect(fns).to.not.include('changeBenefitRate');
            expect(evts).to.not.include('BenefitRateChanged');
        });
    });

    // --- Section 12: _distributeChannelAndDaoBenefits ---
    describe("_distributeChannelAndDaoBenefits", function () {
        it("12.1 channelId>0 + valid: chn +300, DAO +700, harness -1000, returns 9000", async function () {
            const { chnId, signerAddr } = await registerActiveChannel();
            const amount = 10000n;
            await greatLottoCoin.mintFor(harness.address, parseEther('100000'));

            const chnBefore = await greatLottoCoin.balanceOf(signerAddr);
            const daoBefore = await greatLottoCoin.balanceOf(daoBenefitPool.address);
            const hBefore = await greatLottoCoin.balanceOf(harness.address);

            const ret = await harness.distributeChannelAndDaoBenefits.staticCall(greatLottoCoin.address, amount, chnId);
            await harness.distributeChannelAndDaoBenefits(greatLottoCoin.address, amount, chnId);

            expect(ret).to.equal(9000n);
            expect(await greatLottoCoin.balanceOf(signerAddr) - chnBefore).to.equal(300n);
            expect(await greatLottoCoin.balanceOf(daoBenefitPool.address) - daoBefore).to.equal(700n);
            expect(hBefore - await greatLottoCoin.balanceOf(harness.address)).to.equal(1000n);
        });

        it("12.2 channelId==0: channel addr unchanged, DAO +1000, harness -1000, returns 9000", async function () {
            const { signerAddr } = await registerActiveChannel();
            const amount = 10000n;
            await greatLottoCoin.mintFor(harness.address, parseEther('100000'));

            const chnBefore = await greatLottoCoin.balanceOf(signerAddr);
            const daoBefore = await greatLottoCoin.balanceOf(daoBenefitPool.address);
            const hBefore = await greatLottoCoin.balanceOf(harness.address);

            const ret = await harness.distributeChannelAndDaoBenefits.staticCall(greatLottoCoin.address, amount, 0);
            await harness.distributeChannelAndDaoBenefits(greatLottoCoin.address, amount, 0);

            expect(ret).to.equal(9000n);
            expect(await greatLottoCoin.balanceOf(signerAddr)).to.equal(chnBefore);
            expect(await greatLottoCoin.balanceOf(daoBenefitPool.address) - daoBefore).to.equal(1000n);
            expect(hBefore - await greatLottoCoin.balanceOf(harness.address)).to.equal(1000n);
        });

        it("12.3 channelId>0 nonexistent: revert SalesChannelInvalid + DAO unchanged", async function () {
            const amount = 10000n;
            await greatLottoCoin.mintFor(harness.address, parseEther('100000'));
            const daoBefore = await greatLottoCoin.balanceOf(daoBenefitPool.address);
            await expect(harness.distributeChannelAndDaoBenefits(greatLottoCoin.address, amount, 9999))
                .to.be.revertedWithCustomError(salesChannel, "SalesChannelInvalid").withArgs(ZeroAddress);
            expect(await greatLottoCoin.balanceOf(daoBenefitPool.address)).to.equal(daoBefore);
        });

        it("12.4 channelId>0 + disabled (status=false, chn!=0): still pays channel + DAO sell", async function () {
            const { chnId, signerAddr } = await registerActiveChannel();
            // owner disable channel
            const ownerSigner = await ethers.getImpersonatedSigner(ownerAddress);
            await ethers.provider.send("hardhat_setBalance", [ownerAddress, "0x1000000000000000000"]);
            await salesChannel.connect(ownerSigner).disableChannel(chnId);

            const amount = 10000n;
            await greatLottoCoin.mintFor(harness.address, parseEther('100000'));
            const chnBefore = await greatLottoCoin.balanceOf(signerAddr);
            const daoBefore = await greatLottoCoin.balanceOf(daoBenefitPool.address);

            await harness.distributeChannelAndDaoBenefits(greatLottoCoin.address, amount, chnId);
            expect(await greatLottoCoin.balanceOf(signerAddr) - chnBefore).to.equal(300n);
            expect(await greatLottoCoin.balanceOf(daoBenefitPool.address) - daoBefore).to.equal(700n);
        });

        it("12.5 余额不足 revert ErrorInsufficientBalance", async function () {
            const { chnId } = await registerActiveChannel();
            // harness 没有任何 GLC
            await expect(harness.distributeChannelAndDaoBenefits(greatLottoCoin.address, 10000n, chnId))
                .to.be.revertedWithCustomError(harness, "ErrorInsufficientBalance");
        });

        it("12.6 两档 rate==0: no transfers, returns amountByCoin", async function () {
            const ctx = await loadFixture(InitFixtureZeroRates);
            const zHarness = ctx.harness;
            const { chnId, signerAddr } = await registerActiveChannel(ctx.salesChannel, channelOwnerAddress, "zero-chn");

            await ctx.greatLottoCoin.mintFor(zHarness.address, parseEther('1000'));
            const chnBefore = await ctx.greatLottoCoin.balanceOf(signerAddr);
            const daoBefore = await ctx.greatLottoCoin.balanceOf(ctx.daoBenefitPool.address);
            const hBefore = await ctx.greatLottoCoin.balanceOf(zHarness.address);

            const ret = await zHarness.distributeChannelAndDaoBenefits.staticCall(ctx.greatLottoCoin.address, 10000n, chnId);
            await zHarness.distributeChannelAndDaoBenefits(ctx.greatLottoCoin.address, 10000n, chnId);

            expect(ret).to.equal(10000n);
            expect(await ctx.greatLottoCoin.balanceOf(signerAddr)).to.equal(chnBefore);
            expect(await ctx.greatLottoCoin.balanceOf(ctx.daoBenefitPool.address)).to.equal(daoBefore);
            expect(await ctx.greatLottoCoin.balanceOf(zHarness.address)).to.equal(hBefore);
        });

        it("12.7 整数除法边界 amount=1: channelBenefit=0, sellBenefit=0, ret=1, no transfer", async function () {
            const { chnId, signerAddr } = await registerActiveChannel();
            await greatLottoCoin.mintFor(harness.address, parseEther('10'));
            const chnBefore = await greatLottoCoin.balanceOf(signerAddr);
            const daoBefore = await greatLottoCoin.balanceOf(daoBenefitPool.address);
            const hBefore = await greatLottoCoin.balanceOf(harness.address);

            const ret = await harness.distributeChannelAndDaoBenefits.staticCall(greatLottoCoin.address, 1n, chnId);
            await harness.distributeChannelAndDaoBenefits(greatLottoCoin.address, 1n, chnId);
            expect(ret).to.equal(1n);
            expect(await greatLottoCoin.balanceOf(signerAddr)).to.equal(chnBefore);
            expect(await greatLottoCoin.balanceOf(daoBenefitPool.address)).to.equal(daoBefore);
            expect(await greatLottoCoin.balanceOf(harness.address)).to.equal(hBefore);
        });
    });

    // --- Section 13: 付奖兜底 push→pull (_recordPendingPayout / claimPayout / pendingPayoutOf) ---
    describe("payout fallback", function () {
        // 取一个真实 signer 作为领款人（claimPayout 以 msg.sender 记账）
        let claimant;
        beforeEach(async () => {
            claimant = await ethers.getImpersonatedSigner(buyerAddress);
            await ethers.provider.send("hardhat_setBalance", [buyerAddress, "0x1000000000000000000"]);
        });

        it("13.1 pendingPayoutOf defaults to 0", async function () {
            expect(await harness.pendingPayoutOf(buyerAddress)).to.equal(0n);
        });

        it("13.2 recordPendingPayout accrues amount + emits PayoutPending(user, GLC, amount)", async function () {
            await expect(harness.recordPendingPayout(buyerAddress, parseEther('3')))
                .to.emit(harness, "PayoutPending").withArgs(buyerAddress, greatLottoCoin.address, parseEther('3'));
            expect(await harness.pendingPayoutOf(buyerAddress)).to.equal(parseEther('3'));

            // 二次记账累加
            await harness.recordPendingPayout(buyerAddress, parseEther('2'));
            expect(await harness.pendingPayoutOf(buyerAddress)).to.equal(parseEther('5'));
        });

        it("13.3 claimPayout with no pending reverts ErrorNoPendingPayout", async function () {
            await expect(harness.connect(claimant).claimPayout())
                .to.be.revertedWithCustomError(harness, "ErrorNoPendingPayout");
        });

        it("13.4 claimPayout pays GLC, zeroes balance, emits PayoutClaimed", async function () {
            await harness.recordPendingPayout(buyerAddress, parseEther('5'));
            // 给 harness 充值 GLC 以支付兜底欠款
            await greatLottoCoin.mintFor(harness.address, parseEther('5'));

            const balBefore = await greatLottoCoin.balanceOf(buyerAddress);
            await expect(harness.connect(claimant).claimPayout())
                .to.emit(harness, "PayoutClaimed").withArgs(buyerAddress, greatLottoCoin.address, parseEther('5'));
            expect(await greatLottoCoin.balanceOf(buyerAddress)).to.equal(balBefore + parseEther('5'));
            expect(await harness.pendingPayoutOf(buyerAddress)).to.equal(0n);
        });

        it("13.5 second claimPayout after draining reverts ErrorNoPendingPayout", async function () {
            await harness.recordPendingPayout(buyerAddress, parseEther('5'));
            await greatLottoCoin.mintFor(harness.address, parseEther('5'));
            await harness.connect(claimant).claimPayout();
            await expect(harness.connect(claimant).claimPayout())
                .to.be.revertedWithCustomError(harness, "ErrorNoPendingPayout");
        });
    });

    // --- Section 14: 软付款 _softPay / _payoutTransfer + 兜底聚合 pendingPayoutTotal ---
    describe("soft pay", function () {
        let claimant;
        beforeEach(async () => {
            claimant = await ethers.getImpersonatedSigner(buyerAddress);
            await ethers.provider.send("hardhat_setBalance", [buyerAddress, "0x1000000000000000000"]);
        });

        it("14.1 _payoutTransfer 外部直调被守卫拒绝 ErrorUnauthorizedSelfCall", async function () {
            await expect(harness["_payoutTransfer"](recipientAddress, parseEther('1')))
                .to.be.revertedWithCustomError(harness, "ErrorUnauthorizedSelfCall");
        });

        it("14.2 softPay 成功：recipient +amount、harness -amount、不记兜底、聚合不变", async function () {
            const amount = parseEther('5');
            await greatLottoCoin.mintFor(harness.address, parseEther('10'));
            const recipBefore = await greatLottoCoin.balanceOf(recipientAddress);
            const harnessBefore = await greatLottoCoin.balanceOf(harness.address);

            await harness.softPay(recipientAddress, amount);

            expect(await greatLottoCoin.balanceOf(recipientAddress) - recipBefore).to.equal(amount);
            expect(harnessBefore - await greatLottoCoin.balanceOf(harness.address)).to.equal(amount);
            expect(await harness.pendingPayoutOf(recipientAddress)).to.equal(0n);
            expect(await harness.pendingPayoutTotal()).to.equal(0n);
        });

        it("14.3 softPay 转账失败（余额不足）：不 revert、转兜底、聚合自增、harness 余额不变", async function () {
            const amount = parseEther('5');
            // 故意不给 harness 充值 → _transferTo 余额不足 revert → _softPay catch 转兜底
            const harnessBefore = await greatLottoCoin.balanceOf(harness.address);

            await expect(harness.softPay(recipientAddress, amount))
                .to.emit(harness, "PayoutPending").withArgs(recipientAddress, greatLottoCoin.address, amount);

            expect(await harness.pendingPayoutOf(recipientAddress)).to.equal(amount);
            expect(await harness.pendingPayoutTotal()).to.equal(amount);
            // 资金留存（这里本就没有，余额不变）
            expect(await greatLottoCoin.balanceOf(harness.address)).to.equal(harnessBefore);
        });

        it("14.4 softPay amount==0：不 revert、不记兜底", async function () {
            await expect(harness.softPay(recipientAddress, 0)).not.to.be.reverted;
            expect(await harness.pendingPayoutOf(recipientAddress)).to.equal(0n);
            expect(await harness.pendingPayoutTotal()).to.equal(0n);
        });

        it("14.5 pendingPayoutTotal == Σ pendingPayoutOf（多用户记账）", async function () {
            await harness.recordPendingPayout(buyerAddress, parseEther('3'));
            await harness.recordPendingPayout(recipientAddress, parseEther('7'));
            await harness.recordPendingPayout(buyerAddress, parseEther('2')); // buyer 累加到 5
            expect(await harness.pendingPayoutOf(buyerAddress)).to.equal(parseEther('5'));
            expect(await harness.pendingPayoutOf(recipientAddress)).to.equal(parseEther('7'));
            expect(await harness.pendingPayoutTotal()).to.equal(parseEther('12'));
        });

        it("14.6 claimPayout 后聚合同步自减配平", async function () {
            await harness.recordPendingPayout(buyerAddress, parseEther('5'));
            await harness.recordPendingPayout(recipientAddress, parseEther('7'));
            expect(await harness.pendingPayoutTotal()).to.equal(parseEther('12'));

            await greatLottoCoin.mintFor(harness.address, parseEther('5'));
            await harness.connect(claimant).claimPayout(); // buyer 提走 5

            expect(await harness.pendingPayoutOf(buyerAddress)).to.equal(0n);
            // 聚合减去 buyer 的 5，仅剩 recipient 的 7
            expect(await harness.pendingPayoutTotal()).to.equal(parseEther('7'));
            expect(await harness.pendingPayoutTotal()).to.equal(await harness.pendingPayoutOf(recipientAddress));
        });
    });

});
