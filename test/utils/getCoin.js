const { ethers } = require("hardhat");
const DAI_ABI = require("../abi/dai_abi.json");
const USDT_ABI = require("../abi/usdt_abi.json");
const PERMIT_ABI = require('../abi/permit_abi.json')
const WETH_ABI = require('../abi/weth_abi.json')
const { parseEther } = ethers;

var USDT_ADDRESS = "0xdac17f958d2ee523a2206206994597c13d831ec7";
var USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
var DAI_ADDRESS = "0x6b175474e89094c44da98b954eedeac495271d0f";
var WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
//var stETH_ADDRESS = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";

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
    /*console.log('balanceTo: ', ethers.formatUnits(balanceTo, decimal))
    console.log('balanceFrom: ', ethers.formatUnits(balanceFrom, decimal))
    console.log('val: ', ethers.formatUnits(val, decimal))
    console.log('fromEth: ', await ethers.provider.getBalance(fromAddr))*/
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
async function getDAICoin(toAddr, val) {
    var addr = "0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B";
    await getCoin('DAI', DAI_ADDRESS, DAI_ABI, addr, toAddr, val);
}
async function getWETHCoin(toAddr, val) {
    var addr = "0x6B44ba0a126a2A1a8aa6cD1AdeeD002e141Bcd44";
    await getCoin('WETH', WETH_ADDRESS, WETH_ABI, addr, toAddr, val);
}



// 授权
async function approveUSDCCoin(owner, allowanceAddr, val) {
    await approveCoin('USDC', USDC_ADDRESS, USDT_ABI, owner, allowanceAddr, val);
}
async function approveUSDTCoin(owner, allowanceAddr, val) {
    await approveCoin('USDT', USDT_ADDRESS, USDT_ABI, owner, allowanceAddr, val);
}
async function approveDAICoin(owner, allowanceAddr, val) {
    await approveCoin('DAI', DAI_ADDRESS, DAI_ABI, owner, allowanceAddr, val);
}
async function approveWETHCoin(owner, allowanceAddr, val) {
    await approveCoin('WETH', WETH_ADDRESS, WETH_ABI, owner, allowanceAddr, val);
}
/*async function approveStETHCoin(owner, allowanceAddr, val) {
    await approveCoin('stETH', stETH_ADDRESS, WETH_ABI, owner, allowanceAddr, val);
}*/

async function getUSDCBalance(addr) {
    return await getBalance(USDC_ADDRESS, USDT_ABI, addr);
}
async function getUSDTBalance(addr) {
    return await getBalance(USDT_ADDRESS, USDT_ABI, addr);
}
async function getDAIBalance(addr) {
    return await getBalance(DAI_ADDRESS, DAI_ABI, addr);
}
async function getWETHBalance(addr) {
    return await getBalance(WETH_ADDRESS, WETH_ABI, addr);
}
/*async function getStETHBalance(addr) {
    return await getBalance(stETH_ADDRESS, WETH_ABI, addr);
}*/

// exports 
module.exports = {
    getUSDTCoin,
    getUSDCCoin,
    getDAICoin,
    getWETHCoin,
    //getStETHCoin,

    approveUSDTCoin,
    approveUSDCCoin,
    approveDAICoin,
    approveWETHCoin,
    //approveStETHCoin,

    getUSDCBalance,
    getUSDTBalance,
    getDAIBalance,
    getWETHBalance,
    //getStETHBalance,

    USDT_ADDRESS,
    USDC_ADDRESS,
    DAI_ADDRESS,
    WETH_ADDRESS,
    //stETH_ADDRESS,

    USDT_DECIMALS: 6,
    USDC_DECIMALS: 6,
    DAI_DECIMALS: 18,
    WETH_DECIMALS: 18,
    //stETH_DECIMALS: 18,
    GLC_DECIMALS: 18,
    GLETH_DECIMALS: 18,

    WETH_ABI,
    //stETH_ABI: WETH_ABI,
    DAI_ABI,
    USDT_ABI,
    USDC_ABI: PERMIT_ABI,
    GLC_ABI: PERMIT_ABI,
    GLETH_ABI: PERMIT_ABI,

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
  
