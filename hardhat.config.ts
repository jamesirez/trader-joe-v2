import { HardhatUserConfig } from "hardhat/config";

import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-typechain";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
// import 'hardhat-contract-sizer';
// import 'hardhat-gas-reporter';
import { HardhatNetworkAccountsUserConfig } from "hardhat/types";

const PRIVATE_KEY: string = process.env.PRIVATE_KEY as string;
const STAKER_KEY: string = process.env.STAKER_KEY as string;

const accounts: HardhatNetworkAccountsUserConfig = {
  mnemonic: "test test test test test test test test test test test tank",
};

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
          },
        },
      },
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
          },
        },
      },
    ],
  },
  defaultNetwork: "tenderly",
  networks: {
    hardhat: {
      tags: process.env.DEFAULT_TAG
        ? process.env.DEFAULT_TAG.split(",")
        : ["local"],
      live: false,
      saveDeployments: false,
      allowUnlimitedContractSize: true,
      chainId: 1,
      accounts,
    },
    tenderly: {
      tags: ["production"],
      live: true,
      saveDeployments: true,
      loggingEnabled: true,
      url: process.env?.TENDERLY_RPC,
      accounts: [PRIVATE_KEY],
    },
    avax_mainnet: {
      tags: ["production"],
      live: true,
      saveDeployments: true,
      loggingEnabled: true,
      url: process.env?.AVAX_MAINNET,
      accounts: [PRIVATE_KEY],
    },
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 200000,
  },
  // contractSizer: {
  //   alphaSort: true,
  //   runOnCompile: true,
  //   disambiguatePaths: false,
  // },
};

export default config;
