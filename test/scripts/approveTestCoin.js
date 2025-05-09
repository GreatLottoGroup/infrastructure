var getCoin = require('../utils/getCoin');

async function main() {

    const buyerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
    //const buyerAddress = '0x3073C55429dE7D46A65Ef092d4B05E4644891cEF';
    const coinAddress='0x0D92d35D311E54aB8EEA0394d7E773Fc5144491a';

    await getCoin.approveDAICoin(buyerAddress, coinAddress, 0);
    await getCoin.approveUSDCCoin(buyerAddress, coinAddress, 0);
    await getCoin.approveUSDTCoin(buyerAddress, coinAddress, 0);
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });