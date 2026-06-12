// Hardhat 仅负责部署（Ignition）与 ABI 产出；合约测试已迁至 Foundry（forge test）。
require("@nomicfoundation/hardhat-toolbox");
require('hardhat-contract-sizer');
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
    version: "0.8.24",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },

  // toolbox 加载时会写 config.gasReporter.enabled，需保留该键；测试已迁 Foundry，置 false。
  gasReporter: {
    enabled: false
  },

  networks: {
    hardhat: {
      forking: {
        url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        blockNumber: 472312054,
      },
      timeout: 1000000
    },
    base: {
        url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        chainId: 8453,
        accounts: [process.env.DEPLOY_ACCOUNT_PRIVATE_KEY],
    },
    baseSepolia: {
        url: `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        chainId: 84532,
        accounts: [process.env.DEPLOY_ACCOUNT_PRIVATE_KEY],
    },
    arbitrum: {
        url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        chainId: 42161,
        accounts: [process.env.DEPLOY_ACCOUNT_PRIVATE_KEY],
    },
    arbitrumSepolia: {
        url: `https://arb-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        chainId: 421614,
        accounts: [process.env.DEPLOY_ACCOUNT_PRIVATE_KEY],
    }
  },

  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false
  },

  etherscan: {
    // apiKey 的 key 必须与链名（内置链名 / customChains[].network）一致
    // arbitrumOne(42161) 用 hardhat-verify 内置链配置，无需 customChain
    apiKey: {
        base: `${process.env.BASESCAN_API_KEY}`,
        baseSepolia: `${process.env.BASESCAN_API_KEY}`,
        arbitrumOne: `${process.env.ARBISCAN_API_KEY}`,
        arbitrumSepolia: `${process.env.ARBISCAN_API_KEY}`,
    },
    customChains: [
        {
            network: "base",
            chainId: 8453,
            urls: {
              apiURL: "https://api.basescan.org/api",
              browserURL: "https://basescan.org",
            },
        },
        {
            network: "baseSepolia",
            chainId: 84532,
            urls: {
              apiURL: "https://api-sepolia.basescan.org/api",
              browserURL: "https://sepolia.basescan.org",
            },
        },
        {
            network: "arbitrumSepolia",
            chainId: 421614,
            urls: {
              apiURL: "https://api-sepolia.arbiscan.io/api",
              browserURL: "https://sepolia.arbiscan.io",
            },
        }
    ]
  },


};
