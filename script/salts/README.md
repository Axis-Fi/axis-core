# Salts

This document provides instructions on how to generate and use salts for CREATE2 deployments to deterministic addresses.

## Tasks

### Generating AuctionHouse Salts

For aesthetic reasons, the AuctionHouse contracts may need to be deployed at deterministic addresses.

For the AtomicAuctionHouse and BatchAuctionHouse, a specific script can be used to generate the addresses with a desired prefix.

Assuming that the developer wants to deploy an AtomicAuctionHouse at an address that will start with `0xAA`, the following command would be run:

```bash
./script/salts/auctionHouse/auction_house_salts.sh --type atomic --prefix AA
```

The generated salt would be stored in `./script/salts/salts.json` under the key `AtomicAuctionHouse` and a hash of the bytecode. Provided the bytecode is the same, the same salt can be used to deploy the contract at the same address on different chains.

### Generating Salts for Any Contract

For aesthetic, gas or other reasons, certain contracts will need to be deployed at deterministic addresses.

The following steps need to be followed to generate the salt:

1. Generate the bytecode file and write it to disk. See `AuctionHouseSalts.s.sol` for an example.

1. Run the salts script with the desired prefix, salt key and bytecode hash. For example:

```bash
./scripts/salts/write_salt.sh ./bytecode/MockCallback98.bin 98 MockCallback 0x5080f4a157b896da527e936ac326bc3742c5d0239c63823b4d5c9939cc19ccb1
```

Provided the contract bytecode (contract code and constructor arguments) is the same, the saved salt will be used during deployment.
