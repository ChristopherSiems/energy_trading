import { readFileSync } from "fs";
import { task } from "hardhat/config";
import { resolve } from "path";
import { EnergyTrade__factory } from "../typechain-types";

task("audit", "Audit the trade history of the contract").setAction(async () => {
  const { ethers } = require("hardhat");
  const energyContract = EnergyTrade__factory.connect(
    JSON.parse(readFileSync(resolve(__dirname, "../deployed.json"), "utf-8"))[
      "contractAddr"
    ],
    ethers.provider,
  );

  for (let i = 0; i < (await energyContract.currBucketID()); i++) {
    console.log(`Bucket ${i}`);
    const [
      clearingPrice,
      tradeCount,
      energyAmounts,
      buyerAddrs,
      sellerAddrs,
      supplieds,
    ] = await energyContract.getTradeBucket(i);

    console.log(`Clearing price: ${clearingPrice}`);
    console.log(`Trade count: ${tradeCount}`);

    for (let j = 0; j < tradeCount; j++) {
      console.log(`\nTrade ${j}`);
      console.log(`Buyer: ${buyerAddrs[j]}`);
      console.log(`Seller: ${sellerAddrs[j]}`);
      console.log(`Energy amount: ${energyAmounts[j]}`);
      console.log(`Supplieds: ${supplieds[j]}`);
    }
  }
});
