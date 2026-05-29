var getCoin = require('../utils/getCoin');

async function main() {

    let addressList = [
        '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
        '0x3073C55429dE7D46A65Ef092d4B05E4644891cEF',
        '0x073b4945e91Ec51E40eD55D76c1435AF626f3d02'
    ]

    for(let i = 0; i < addressList.length; i++){
        let addr = addressList[i];
        let amount = 100000;
        // 买入 10000 USDT
        await getCoin.getUSDTCoin(addr, amount);
        // 买入 10000 USDC
        await getCoin.getUSDCCoin(addr, amount);
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
