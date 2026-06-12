// 合约部署
const { ethers } = require("hardhat");

async function initContract(contractName, ...args){
    const contract = await ethers.deployContract(contractName, [...args]);
    await contract.waitForDeployment();
    contract.address = await contract.getAddress();
    console.log(contractName + " deployed to:", contract.address);
    return contract;
}

async function deploy(config) {
    let { ownerAddress, coinContractName, tokens } = config || {};

    ownerAddress = ownerAddress || '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    coinContractName = coinContractName || 'GreatLottoCoinTest';
    // GreatLottoCoin._tokens 现为构造参数（不再硬编码）。fork 测试默认主网 USDT / USDC。
    tokens = tokens || [
        '0xaf88d065e77c8cC2239327C5EDb3A432268e5831', // USDC
    ];

    // GreatLottoCoin 初始化
    const greatLottoCoin = await initContract(coinContractName, tokens, ownerAddress);

    // DaoCoin 初始化
    const daoCoin = await initContract("DaoCoin", ownerAddress);

    // DaoBenefitPool 初始化
    const daoBenefitPool = await initContract("DaoBenefitPool", greatLottoCoin.address, daoCoin.address);

    // SalesChannel 初始化
    const salesChannel = await initContract("SalesChannel", ownerAddress);

    // PartnerTest 初始化
    const partnerTest = await initContract("PartnerTest", greatLottoCoin.address, daoCoin.address);

    const PARTNER_CONTRACT_ROLE = ethers.solidityPackedKeccak256(["string"], ["PARTNER_CONTRACT_ROLE"]);

    // 设置 GreatLottoCoin caller
    await greatLottoCoin.grantRole(PARTNER_CONTRACT_ROLE, partnerTest.address);
    // 设置 DaoCoin caller
    await daoCoin.grantRole(PARTNER_CONTRACT_ROLE, partnerTest.address);

    console.log('------------');
    console.log('"GreatCoinContractAddress": "%s",', greatLottoCoin.address);
    console.log('"DaoCoinContractAddress": "%s",', daoCoin.address);
    console.log('"DaoBenefitPoolContractAddress": "%s",', daoBenefitPool.address);
    console.log('"SalesChannelContractAddress": "%s"', salesChannel.address);

    return { greatLottoCoin, daoCoin, daoBenefitPool, salesChannel, partnerTest};

}

// exports
module.exports = {
  initContract,
  deploy
};
