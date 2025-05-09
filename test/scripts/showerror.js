const { ethers } = require("hardhat");
const {abi} = require('../../artifacts/contracts/GreatLottoEth.sol/GreatLottoEth.json')

let interface = new ethers.Interface(abi);
let errorData = '0x6279130200000000000000000000000000000000000000000000000000000000681bb693'
let result = interface.parseError(errorData);

console.log(result)