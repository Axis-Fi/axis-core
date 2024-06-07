import { HardhatUserConfig } from "hardhat/config";

// PLUGINS
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-deploy";
import "solidity-coverage";
import "./lib/uniswap";

// Process Env Variables
import * as dotenv from "dotenv";
dotenv.config({ path: __dirname + "/.env" });
const DEPLOYER_PK = process.env.DEPLOYER_PK;

const config: HardhatUserConfig = {
  defaultNetwork: "axisBlast",

  // hardhat-deploy
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },

  // etherscan: {
  //   apiKey: process.env.ETHERSCAN_API_KEY,
  // },

  networks: {
    axisBlast: {
      accounts: DEPLOYER_PK ? [DEPLOYER_PK] : [],
      chainId: 6226,
      url: "https://virtual.blast.rpc.tenderly.co/32f586c8-355a-4898-bf37-4a5de650777e"
    }
  },

  solidity: {
    compilers: [
      {
        version: "0.7.3",
        settings: {
          optimizer: { enabled: true },
        },
      },
      {
        version: "0.8.19",
        settings: {
          optimizer: { enabled: true, runs: 1 },
        },
      },
    ],
  },

  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
