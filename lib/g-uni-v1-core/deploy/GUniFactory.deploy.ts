import { deployments, getNamedAccounts } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getAddresses } from "../src/addresses";
import { isZeroAddress } from "./address";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  if (
    hre.network.name === "mainnet" ||
    hre.network.name === "optimism" ||
    hre.network.name === "polygon"
  ) {
    console.log(
      `!! Deploying GUniFactory to ${hre.network.name}. Hit ctrl + c to abort`
    );
    await new Promise((r) => setTimeout(r, 20000));
  }

  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const addresses = getAddresses(hre.network.name);

  // Validate input addresses
  if (isZeroAddress(addresses.UniswapV3Factory)) {
    throw new Error("UniswapV3Factory address not set");
  }
  if (isZeroAddress(addresses.GelatoDevMultiSig)) {
    throw new Error("GelatoDevMultiSig address not set");
  }
  if (isZeroAddress(addresses.GUniImplementation)) {
    throw new Error("GUniImplementation (pool implementation) address not set");
  }

  const result = await deploy("GUniFactory", {
    from: deployer,
    proxy: {
      proxyContract: "EIP173Proxy",
      owner: addresses.GelatoDevMultiSig,
      execute: {
        init: {
          methodName: "initialize",
          args: [
            addresses.GUniImplementation,
            addresses.GelatoDevMultiSig,
            addresses.GelatoDevMultiSig,
          ],
        },
      },
    },
    args: [addresses.UniswapV3Factory],
  });

  console.log("GUniFactory deployed to:", result.address);
};

func.skip = async (hre: HardhatRuntimeEnvironment) => {
  const shouldSkip =
    hre.network.name === "mainnet" ||
    hre.network.name === "polygon" ||
    hre.network.name === "optimism" ||
    hre.network.name === "goerli";
  return shouldSkip ? true : false;
};

func.tags = ["GUniFactory"];

export default func;
