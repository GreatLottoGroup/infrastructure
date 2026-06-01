const { ethers } = require("hardhat");
const { deploy, initContract } = require('./deployTool');

const PARTNER_CONTRACT_ROLE = ethers.solidityPackedKeccak256(["string"], ["PARTNER_CONTRACT_ROLE"]);

async function deployPrizePoolBaseFixture(opts = {}) {
    const ownerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    const initialChannelRate = opts.channelRate ?? 30;
    const initialSellRate = opts.sellRate ?? 70;

    const base = await deploy();
    const { greatLottoCoin, daoCoin, daoBenefitPool, salesChannel } = base;

    const harness = await initContract(
        "PrizePoolBaseHarness",
        greatLottoCoin.address,
        daoCoin.address,
        daoBenefitPool.address,
        salesChannel.address,
        ownerAddress,
        initialChannelRate,
        initialSellRate
    );

    // harness 需要 PARTNER_CONTRACT_ROLE 才能调 GLC.mint / DaoCoin.mintToUser
    await greatLottoCoin.grantRole(PARTNER_CONTRACT_ROLE, harness.address);
    await daoCoin.grantRole(PARTNER_CONTRACT_ROLE, harness.address);

    return { ...base, harness, ownerAddress, initialChannelRate, initialSellRate };
}

module.exports = {
    deployPrizePoolBaseFixture,
    PARTNER_CONTRACT_ROLE,
};
