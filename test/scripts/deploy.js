const { deploy} = require('../utils/deployTool');
const { parseEther } = ethers;

let addressList = [
    '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
    '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    '0x3073C55429dE7D46A65Ef092d4B05E4644891cEF',
    '0x073b4945e91Ec51E40eD55D76c1435AF626f3d02'
]

const InitializeFixture = async () => {
    // 合约部署
    let contractList = await deploy({
    });

    return contractList;
}

async function main() {

    let contractList = await InitializeFixture();

    for(let i = 0; i < addressList.length; i++){
        await contractList.greatLottoCoin.mintFor(addressList[i], parseEther(10 ** 9 + ''));
    }


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });

