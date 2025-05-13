# Infrastructure
Infrastructure of GreatLottoGroup


```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.js
```


 Test

```shell
npx hardhat node --fork https://eth-mainnet.g.alchemy.com/v2/iyAD5ECTdwibSCZhntMLmhqJnSpNX7eA --fork-block-number 22431796

npx hardhat node --fork https://eth-holesky.g.alchemy.com/v2/iyAD5ECTdwibSCZhntMLmhqJnSpNX7eA --fork-block-number 2360339


npx hardhat clean

npx hardhat compile   

npx hardhat test --network localhost test/runTest/*.js  

npx hardhat coverage --testfiles "test/runTest/*.js"

npx hardhat run --network localhost test/scripts/deploy.js 

npx hardhat run --network localhost test/scripts/initTestCoin.js   

```

Deploy check list:

1. run & pass all test case 
2. check pay token with GreatLottoCoin.sol & GreatLottoEth.sol
3. check deploy account with hardhat.config.js .env
4. check owner account with deploy.js & .env

Deploy by Localhost

```shell

npx hardhat ignition deploy ignition/modules/infrastructure.js --network localhost
npx hardhat ignition deploy ignition/modules/infrastructure.js --network localhost --reset

npx hardhat run scripts/deploy.js --network localhost

```

Deploy by Sepolia

```shell

npx hardhat ignition deploy ignition/modules/infrastructure.js --network sepolia
npx hardhat ignition deploy ignition/modules/infrastructure.js --network sepolia --reset
npx hardhat ignition deploy ignition/modules/infrastructure.js --network sepolia --verify

npx hardhat ignition verify chain-11155111

```

Deploy by Holesky

```shell

npx hardhat ignition deploy ignition/modules/infrastructure.js --network holesky --reset
npx hardhat ignition deploy ignition/modules/infrastructure.js --network holesky --verify

npx hardhat ignition verify chain-17000

```

Publish to NPM

```shell

npm publish --access public

```
