// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

const InfrastructureModule = require("../ignition/modules/infrastructure");

async function main() {

    const { greatLottoCoin, greatLottoEth, daoCoin, daoBenefitPool, salesChannel } = await hre.ignition.deploy(InfrastructureModule);

    console.log('------------');
    console.log('"GreatCoinContractAddress": "%s",', await greatLottoCoin.getAddress());
    console.log('"GreatEthContractAddress": "%s",', await greatLottoEth.getAddress());
    console.log('"DaoCoinContractAddress": "%s",', await daoCoin.getAddress());
    console.log('"DaoBenefitPoolContractAddress": "%s",', await daoBenefitPool.getAddress());
    console.log('"SalesChannelContractAddress": "%s"', await salesChannel.getAddress());

    console.log('------------');
    console.log('GREAT_LOTTO_COIN_ADDRESS="%s"', await greatLottoCoin.getAddress());
    console.log('GREAT_LOTTO_ETH_ADDRESS="%s"', await greatLottoEth.getAddress());
    console.log('DAO_COIN_ADDRESS="%s"', await daoCoin.getAddress());
    console.log('DAO_BENEFIT_POOL_ADDRESS="%s"', await daoBenefitPool.getAddress());
    console.log('SALES_CHANNEL_ADDRESS="%s"', await salesChannel.getAddress());
    

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });