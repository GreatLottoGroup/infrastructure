const { ethers } = require("hardhat");
const USDT_ABI = require("../abi/usdt_abi.json");
const PERMIT_ABI = require('../abi/permit_abi.json')
const { parseEther } = ethers;

var USDT_ADDRESS = "0xdac17f958d2ee523a2206206994597c13d831ec7";
var USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

async function getBalanceByCoin(contract, decimal, addr){
    var balance = await contract.balanceOf(addr);
    return ethers.formatUnits(balance, decimal);
}

async function getAllowance(contract, decimal, owner, addr){
    var allowance = await contract.allowance(owner, addr);
    return ethers.formatUnits(allowance, decimal);
}

// 查询余额
async function getBalance(contractAddr, contractAbi, addr) {
    const CoinContract = new ethers.Contract(contractAddr, contractAbi, ethers.provider);
    var balance = await CoinContract.balanceOf(addr)
    return balance;
}

// 充值
async function getCoin(tokenName, contractAddr, contractAbi, fromAddr, toAddr, val) {
    const impersonatedSigner = await ethers.getImpersonatedSigner(fromAddr);
    const CoinContract = new ethers.Contract(contractAddr, contractAbi, impersonatedSigner);
    const decimal = await CoinContract.decimals();
    val = ethers.parseUnits(val+'', decimal);
    var balanceTo = await CoinContract.balanceOf(toAddr);
    var balanceFrom = await await CoinContract.balanceOf(fromAddr);
    if(balanceTo < val){
        // 金额不够则执行充值
        if(balanceFrom > val){
            var tx = await CoinContract.transfer(toAddr, val);
            await tx.wait();
            console.log(tokenName, 'Successful recharge balance: ', await getBalanceByCoin(CoinContract, decimal, toAddr));
            console.log(tokenName, 'Original account balance: ', await getBalanceByCoin(CoinContract, decimal, fromAddr));
        }else{
            console.log(tokenName, ' balance is not enough', ethers.formatUnits(balanceFrom, decimal));
        }
    }else{
        console.log(tokenName, 'Sufficient balance: ', ethers.formatUnits(balanceTo, decimal));
    }
}

// 授权
async function approveCoin(tokenName, contractAddr, contractAbi, owner, allowanceAddr, val) {
    const impersonatedSigner = await ethers.getImpersonatedSigner(owner);
    const CoinContract = new ethers.Contract(contractAddr, contractAbi, impersonatedSigner);
    const decimal = await CoinContract.decimals();
    var allowanceBalance = await getAllowance(CoinContract, decimal, owner, allowanceAddr);
    if(val == 0 || allowanceBalance < val){
        var tx = await CoinContract.approve(allowanceAddr, ethers.parseUnits(val+'', decimal));
        await tx.wait();
        console.log(tokenName, 'Successful approval: ', await getAllowance(CoinContract, decimal, owner, allowanceAddr));
    }else{
        console.log(tokenName, 'Sufficient approval: ', allowanceBalance);
    }

}

// 充值
async function getUSDCCoin(toAddr, val) {
    var addr = "0x51eDF02152EBfb338e03E30d65C15fBf06cc9ECC";
    await getCoin('USDC', USDC_ADDRESS, USDT_ABI, addr, toAddr, val);
}
async function getUSDTCoin(toAddr, val) {
    var addr = "0xA7A93fd0a276fc1C0197a5B5623eD117786eeD06";
    await getCoin('USDT', USDT_ADDRESS, USDT_ABI, addr, toAddr, val);
}

// 授权
async function approveUSDCCoin(owner, allowanceAddr, val) {
    await approveCoin('USDC', USDC_ADDRESS, USDT_ABI, owner, allowanceAddr, val);
}
async function approveUSDTCoin(owner, allowanceAddr, val) {
    await approveCoin('USDT', USDT_ADDRESS, USDT_ABI, owner, allowanceAddr, val);
}

async function getUSDCBalance(addr) {
    return await getBalance(USDC_ADDRESS, USDT_ABI, addr);
}
async function getUSDTBalance(addr) {
    return await getBalance(USDT_ADDRESS, USDT_ABI, addr);
}

// exports
module.exports = {
    getUSDTCoin,
    getUSDCCoin,

    approveUSDTCoin,
    approveUSDCCoin,

    getUSDCBalance,
    getUSDTBalance,

    USDT_ADDRESS,
    USDC_ADDRESS,

    USDT_DECIMALS: 6,
    USDC_DECIMALS: 6,
    GLC_DECIMALS: 18,

    USDT_ABI,
    USDC_ABI: PERMIT_ABI,
    GLC_ABI: PERMIT_ABI,

    greatCoinTools: function(coinObj, coinName){
        let tools= {};
        tools[coinName + '_ADDRESS'] = coinObj.address;
        tools['get' + coinName + 'Coin'] = async function(toAddr, val){
            await coinObj.mintFor(toAddr, parseEther(val + ''));
        };
        tools['approve' + coinName + 'Coin'] = async function(owner, allowanceAddr, val){
            await approveCoin(coinName, coinObj.address, USDT_ABI, owner, allowanceAddr, val);
        };
        tools['get' + coinName + 'Balance'] = async function(addr){
            return await coinObj.balanceOf(addr);
        };
        return tools
    }
};
