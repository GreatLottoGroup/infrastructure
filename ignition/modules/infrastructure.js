const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
require('dotenv').config()

// Owner账户
const ownerAddress = process.env.OWNER_ADDRESS

// GreatLottoCoin._tokens 现为构造参数（按部署网络传入支持的稳定币地址）。
// 主网/L2 真实地址；测试网请替换为对应测试币地址。
const supportedTokens = [
    '0xdAC17F958D2ee523a2206206994597C13D831ec7', // USDT
    '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
];

module.exports = buildModule("Infrastructure", (m) => {

    // GreatLottoCoin 初始化
    //const greatLottoCoin = m.contract("GreatLottoCoin", [supportedTokens, ownerAddress]);
    const greatLottoCoin = m.contract("GreatLottoCoinTest", [supportedTokens, ownerAddress]);

    // DaoCoin 初始化
    const daoCoin = m.contract("DaoCoin", [ownerAddress]);

    // DaoBenefitPool 初始化
    const daoBenefitPool = m.contract("DaoBenefitPool", [greatLottoCoin, daoCoin]);

    // SalesChannel 初始化
    const salesChannel = m.contract("SalesChannel", [ownerAddress]);


    return { greatLottoCoin, daoCoin, daoBenefitPool, salesChannel };
});
