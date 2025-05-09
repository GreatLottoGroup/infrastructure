const { getSignMessage } = require('../utils/permitUtils');

const PERMIT_ABI = require('../abi/permit_abi.json')


async function main() {

    let sign = await getSignMessage("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", PERMIT_ABI, "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", "0xF02929e7C529FACD2d6510A50cC7137CDbd3717c", 630000000n, 1712513790n);

    console.log(sign);
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });