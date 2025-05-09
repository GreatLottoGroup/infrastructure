const { ethers } = require("hardhat");
const { parseEther } = ethers;

// 测试分润计算
async function benefitCompute(beneficiaryList, totalAmount, totalSupply, BenefitMinShares) {
    totalAmount = parseEther(totalAmount + '');
    let _beneficiaryList = [...beneficiaryList]
    let benefitList = [];
    let totalBenefitAmount = 0n;
    // 分润
    for (let i = 0; i < _beneficiaryList.length; i++) {
        _beneficiaryList[i] = parseEther(_beneficiaryList[i] + '');
        if(_beneficiaryList[i] < BenefitMinShares){
            benefitList[i] = 0n;
        }else{
            benefitList[i] = _beneficiaryList[i] * totalAmount / BigInt(totalSupply);
            totalBenefitAmount += benefitList[i];
        }
    }
    // 最终分润
    /*
    console.log('benefitList: ', benefitList);
    console.log('totalBenefitAmount: ', formatEther(totalBenefitAmount));
    */
    return [benefitList, totalBenefitAmount];
}


module.exports = {
    benefitCompute,
};