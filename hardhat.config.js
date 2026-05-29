require("@nomicfoundation/hardhat-toolbox");
require('hardhat-contract-sizer');
require('solidity-coverage');
require("hardhat-gas-reporter");
require('dotenv').config()
require("@nomicfoundation/hardhat-ignition-ethers");

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();
  for (const account of accounts) {
    console.log(account.address);
  }
});


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: "hardhat",
  
  solidity: {
    version: "0.8.35",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: false,
        runs: 200
      }
    }
  },

  gasReporter: {
    enabled: true,
    currency: 'USD'
  }, 

  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        blockNumber: 22128216,
      },
      timeout: 1000000
    },
    mainnet: {
        url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        accounts: [process.env.DEPLOY_ACCOUNT_PRIVATE_KEY],
        ignition: {
            maxFeePerGasLimit: 2_000_000_000n, // 2 gwei
            maxPriorityFeePerGas: 1_000_000_000n, // 1 gwei
        },
    },
    sepolia: {
        url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        accounts: [process.env.DEPLOY_ACCOUNT_PRIVATE_KEY],
        ignition: {
            maxFeePerGasLimit: 5_000_000_000n, // 5 gwei
            maxPriorityFeePerGas: 1_000_000_000n, // 1 gwei
        },
    },
    holesky: {
        url: `https://eth-holesky.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        chainId: 17000,
        accounts: [process.env.DEPLOY_ACCOUNT_PRIVATE_KEY],
        ignition: {
            //maxFeePerGasLimit: 1_000_000_000n, // 1 gwei
            //maxPriorityFeePerGas: 1_000_000_000n, // 1 gwei
        },
    }
  },

  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false
  },

  mocha: {
    timeout: 1000000
  },

  etherscan: {
    apiKey: `${process.env.ETHERSCAN_API_KEY}`,
    customChains: [
        {
            network: "holesky",
            chainId: 17000,
            urls: {
              apiURL: "https://api-holesky.etherscan.io/api",
              browserURL: "https://holesky.etherscan.io",
            },
          }
    ]
  },


};
