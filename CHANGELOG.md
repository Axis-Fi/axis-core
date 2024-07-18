# Changelog

## 1.0.0

- Initial production deployments to arbitrum, base, blast, and mantle

## 0.9.0

- Split periphery (callbacks) contracts out into a new repository: `axis-fi/axis-periphery`
- Split some scripts out into a new repository: `axis-fi/axis-utils`
- Use soldeer instead of git submodules for external dependencies
- Change absolute imports to relative imports so that it can be used as a dependency

## 0.5.1

- Migrates all dependencies over to soldeer packages and away from git submodules (#222)
- Removes redundant dependencies (prb-math, uniswap-v3-periphery) (#222)
- Packages the repository as a soldeer package (#222)
- Use implicit imports in interfaces (#223)
- Improvements to constant and deployment addresses (#220)

## 0.5.0

- Adds SVG for derivative tokens deployed using the LinearVesting module (#210)
- Define the referrer fee on a per-auction basis (#216)
- Standardise percentages on 2 basis points (100% = 100e2)
