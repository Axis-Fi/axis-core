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

const config: HardhatUserConfig = {

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
    anvil: {
      chainId: 31337,
      url: "http://localhost:8545",
      accounts: [process.env.ANVIL_PRIVATE_KEY ?? ""],
    },
    blastSepolia: {
      chainId: 168587773,
      url: process.env.BLAST_SEPOLIA_RPC || "https://sepolia.blast.io",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY ?? ""],
    },
    arbitrumSepolia: {
      chainId: 421614,
      url: process.env.ARBITRUM_SEPOLIA_RPC || "https://sepolia-rollup.arbitrum.io/rpc",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY ?? ""],
    },
    modeSepolia: {
      chainId: 919,
      url: process.env.MODE_SEPOLIA_RPC || "https://sepolia.mode.network",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY ?? ""],
    },
    baseSepolia: {
      chainId: 84532,
      url: process.env.BASE_SEPOLIA_RPC || "https://sepolia.base.org",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY ?? ""],
    },
    mantleSepolia: {
      chainId: 5003,
      url: process.env.MANTLE_SEPOLIA_RPC,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY ?? ""]
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
  etherscan: {
    apiKey: process.env[`${process.env.HARDHAT_NETWORK}_ETHERSCAN_API_KEY`],
  }
};

export default config;
