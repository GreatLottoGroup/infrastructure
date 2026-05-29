const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
require('dotenv').config()

// Owner账户
const ownerAddress = process.env.OWNER_ADDRESS

module.exports = buildModule("Infrastructure", (m) => {

    // GreatLottoCoin 初始化
    //const greatLottoCoin = m.contract("GreatLottoCoin", [ownerAddress]);
    const greatLottoCoin = m.contract("GreatLottoCoinTest", [ownerAddress]);

    // DaoCoin 初始化
    const daoCoin = m.contract("DaoCoin", [ownerAddress]);

    // DaoBenefitPool 初始化
    const daoBenefitPool = m.contract("DaoBenefitPool", [greatLottoCoin, daoCoin]);

    // SalesChannel 初始化
    const salesChannel = m.contract("SalesChannel", [ownerAddress]);


    return { greatLottoCoin, daoCoin, daoBenefitPool, salesChannel };
});
