const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

// 部署参数改由 Ignition 参数文件注入（ignition/parameters/<network>.json），不再读 process.env。
// 每条链一份 JSON：
//   - owner：构造时取得 DEFAULT_ADMIN_ROLE 的管理员地址（主网建议 Safe 多签）
//   - supportedTokens：GreatLottoCoin._tokens 稳定币白名单（按目标链填；测试网 / 本地可留空 [])
// 注：当前默认部署 GreatLottoCoinTest（带免费 mint 的测试变体）；主网前须切回 GreatLottoCoin。
module.exports = buildModule("Infrastructure", (m) => {

    const owner = m.getParameter("owner");
    const supportedTokens = m.getParameter("supportedTokens");

    // GreatLottoCoin 初始化
    //const greatLottoCoin = m.contract("GreatLottoCoin", [supportedTokens, owner]);
    const greatLottoCoin = m.contract("GreatLottoCoinTest", [supportedTokens, owner]);

    // DaoCoin 初始化
    const daoCoin = m.contract("DaoCoin", [owner]);

    // DaoBenefitPool 初始化
    const daoBenefitPool = m.contract("DaoBenefitPool", [greatLottoCoin, daoCoin]);

    // SalesChannel 初始化
    const salesChannel = m.contract("SalesChannel", [owner]);


    return { greatLottoCoin, daoCoin, daoBenefitPool, salesChannel };
});
