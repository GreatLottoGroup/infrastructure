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
    version: "0.8.26",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },

  // 测试已迁 Foundry，hardhat-gas-reporter 无 hardhat test 可计、置 false（gas 看 `npm run gas`）。
  // 注：该键不可删——toolbox 加载时会写 gasReporter.enabled，缺键会 TypeError。
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
    // 本地节点（chainId 31337，先 `anvil` 或 `npx hardhat node` 起一个本地链）。
    // 账户用本地节点内置的解锁账号，无需 .env 私钥。
    localhost: {
        // HARDHAT_LOCALHOST_URL lets the e2e harness point this at its dedicated anvil
        // (e.g. :8546) so its deploy never touches a developer's local :8545 dev chain.
        url: process.env.HARDHAT_LOCALHOST_URL || "http://127.0.0.1:8545",
        chainId: 31337,
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
    // Etherscan V2 统一 API：apiKey 必须是「单个字符串」（一把 etherscan.io key 通吃全链）。
    // 传对象（各链独立 key）会被 hardhat-verify 判定为 V1 → 命中已停用的 V1 endpoint
    // （如 api-sepolia.arbiscan.io/api）→ 报 "deprecated V1 endpoint"。
    apiKey: process.env.ETHERSCAN_API_KEY,
    // ⚠️ Ignition 的 --verify 不读 hardhat-verify 的内置 chain-config，而是用 ignition-core
    // 自带的一份**独立且过时**的 builtinChains：base(8453)/arbitrumOne(42161)/
    // arbitrumSepolia(421614) 有，但只收了旧 baseGoerli(84531)、**缺 baseSepolia(84532)**
    // → `ignition deploy --network baseSepolia --verify` 抛 IGN1002。
    // resolveChainConfig 是 [...customChains, ...builtinChains].find()，故在此补一条即可。
    // V2 单串 key 下 Etherscan 类会把 apiURL 覆盖成统一端点 https://api.etherscan.io/v2/api
    // 并附 ?chainid=84532 路由，故下方 apiURL 仅占位、browserURL 用于成功回显链接。
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
    ],
  },


};
