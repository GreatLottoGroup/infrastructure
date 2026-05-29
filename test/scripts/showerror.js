const { ethers } = require("hardhat");
const {abi} = require('../../artifacts/contracts/GreatLottoCoin.sol/GreatLottoCoin.json')

let interface = new ethers.Interface(abi);
let errorData = '0x6279130200000000000000000000000000000000000000000000000000000000681bb693'
let result = interface.parseError(errorData);

console.log(result)
