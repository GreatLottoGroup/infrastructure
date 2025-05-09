const { mineUpTo, setNextBlockBaseFeePerGas } = require("@nomicfoundation/hardhat-network-helpers");
const { network, ethers } = require("hardhat");
const {formatUnits, parseUnits, toBeHex, toBigInt} = ethers

mineUpTo(20316950);

/*
let targetGasPrice = 1000;
setNextBlockBaseFeePerGas(toBeHex(parseUnits(targetGasPrice + '', 'gwei')))
const getGasPrice = async () => {
    const gasPrice = await network.provider.send("eth_gasPrice", []);
    console.log('gasPrice: ', formatUnits(toBigInt(gasPrice), 'gwei'));
}

getGasPrice()
*/