/* eslint-disable @typescript-eslint/naming-convention */
interface Addresses {
  Gelato: string;
  WETH: string;
  DAI: string;
  USDC: string;
  UniswapV3Factory: string;
  Swapper: string;
  GelatoDevMultiSig: string;
  GUniFactory: string;
  GUniImplementation: string;
}

export const getAddresses = (network: string): Addresses => {
  switch (network) {
    case "mainnet":
      return {
        Gelato: "0x3CACa7b48D0573D793d3b0279b5F0029180E83b6",
        Swapper: "",
        GelatoDevMultiSig: "",
        WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        DAI: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        GUniFactory: "0xEA1aFf9dbFfD1580F6b81A3ad3589E66652dB7D9",
        GUniImplementation: "",
      };
    case "optimism":
      return {
        Gelato: "0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef",
        Swapper: "",
        GelatoDevMultiSig: "",
        WETH: "",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        GUniFactory: "0x2845c6929d621e32B7596520C8a1E5a37e616F09",
        GUniImplementation: "0x8582Bf142BE76fEF830D23f590a2587f2aD7C216",
      };
    case "polygon":
      return {
        Gelato: "0x7598e84B2E114AB62CAB288CE5f7d5f6bad35BbA",
        Swapper: "0x2E185412E2aF7DC9Ed28359Ea3193EBAd7E929C6",
        GelatoDevMultiSig: "0x02864B9A53fd250900Ba74De507a56503C3DC90b",
        WETH: "",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        GUniFactory: "0x37265A834e95D11c36527451c7844eF346dC342a",
        GUniImplementation: "0xd2Bb190dD88e7Af5DF176064Ec42f6dfA8672F40",
      };
    case "goerli":
      return {
        Gelato: "0x683913B3A32ada4F8100458A3E1675425BdAa7DF",
        Swapper: "",
        GelatoDevMultiSig: "0x4B5BaD436CcA8df3bD39A095b84991fAc9A226F1",
        WETH: "",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        GUniFactory: "",
        GUniImplementation: "",
      };
    case "anvil":
      return {
        Gelato: "0x0000000000000000000000000000000000000000",
        Swapper: "",
        GelatoDevMultiSig: "0x0000000000000000000000000000000000000000",
        WETH: "0x0000000000000000000000000000000000000000",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "",
        GUniFactory: "",
        GUniImplementation: "",
      };
    case "blastSepolia":
      return {
        Gelato: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        Swapper: "",
        GelatoDevMultiSig: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        WETH: "0x4200000000000000000000000000000000000023",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "0x84fF29e6321c9dd328B8B383b08dd2815b121243",
        GUniFactory: "0xED28E5230E934cf9C843C08818D0639176040297",
        GUniImplementation: "0xdde18C0c3B637F4BA02f5567a671F5e28b7404e7",
      };
    case "arbitrumSepolia":
      return {
        Gelato: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        Swapper: "",
        GelatoDevMultiSig: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        WETH: "",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e",
        GUniFactory: "0x7f502e91182338F19CB6F4B02B33B33feD1c5000",
        GUniImplementation: "0xCE7427a94bc9B8A90E2C8d91cB0247D779819437",
      };
    case "modeSepolia":
      return {
        Gelato: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        Swapper: "",
        GelatoDevMultiSig: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        WETH: "",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "0x0f88f3f5108eB3BD1A2D411E9a1fD41997811D88",
        GUniFactory: "0x2dCC5a88A861FB73613153F82CF801cd09E72a5F",
        GUniImplementation: "0xe1B83edA3399A2c9B8265215EA21042C9b918dc5",
      };
    case "baseSepolia":
      return {
        Gelato: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        Swapper: "",
        GelatoDevMultiSig: "0xB47C8e4bEb28af80eDe5E5bF474927b110Ef2c0e",
        WETH: "",
        DAI: "",
        USDC: "",
        UniswapV3Factory: "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
        GUniFactory: "0x04974BcFC715c148818724d9Caab3Fe8d0391b8b",
        GUniImplementation: "0xF5c31d08a71c854A9f607A5992456dBC31B11e16",
      };
    default:
      throw new Error(`No addresses for Network: ${network}`);
  }
};
