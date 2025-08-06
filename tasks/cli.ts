import { readFileSync } from "fs";
import { task } from "hardhat/config";
import { resolve } from "path";
import { EnergyTrade, EnergyTrade__factory } from "../typechain-types";
import type { LogDescription } from "ethers";

function printEvents(
  receipt: { logs: any[] },
  energyContract: EnergyTrade,
): void {
  receipt.logs
    .map((log) => {
      try {
        return energyContract.interface.parseLog(log);
      } catch {
        return null;
      }
    })
    .filter((parsed): parsed is LogDescription => parsed !== null)
    .forEach((event, i) => {
      console.log(`\nEvent ${i}: ${event.name}`);
      event.fragment.inputs.forEach((input) => {
        const key = input.name;
        const value = event.args[key];
        console.log(`${key}: ${value}`);
      });
    });

  console.log("\n");
}

function printReversion(err: any): void {
  if (err?.reason) console.error("Reversion reason: ", err.reason);
  else if (err?.error?.message)
    console.error("Reversion message: ", err.error.message);
  else console.error("Unknown error: ", err);

  console.log("\n");
}

task(
  "cli",
  "Interact with the `EnergyTrade` contract running on a `localhost` node",
)
  .addParam("account", "Index of the account to use")
  .addParam("cmd", "Command to perform")
  .addOptionalParam("energy", "Energy amount")
  .addOptionalParam("price", "Unit price")
  .addOptionalParam("bucket", "Bucket ID")
  .addOptionalParam("trade", "Trade ID")
  .setAction(async (taskArgs) => {
    const { ethers } = require("hardhat");
    const account: number = parseInt(taskArgs.account);
    const cmd = taskArgs.cmd;
    const { contractAddr, bucketDuration } = JSON.parse(
      readFileSync(resolve(__dirname, "../deployed.json"), "utf-8"),
    );
    const signers = await ethers.getSigners();
    const energyContract = EnergyTrade__factory.connect(contractAddr);

    switch (cmd) {
      case "bid": {
        try {
          const energyAmount = BigInt(taskArgs.energy);
          const unitPrice = BigInt(taskArgs.price);

          const bidTx = await energyContract
            .connect(signers[account])
            .bidRequest(energyAmount, unitPrice, {
              value: energyAmount * unitPrice,
            });

          const bidReceipt = await bidTx.wait();
          if (!bidReceipt) throw new Error("Bid receipt missing");

          printEvents(bidReceipt, energyContract);
        } catch (err: any) {
          console.error("Contract reverted");
          printReversion(err);
        }
        break;
      }
      case "ask": {
        try {
          const energyAmount = BigInt(taskArgs.energy);
          const unitPrice = BigInt(taskArgs.price);

          const askTx = await energyContract
            .connect(signers[account])
            .askRequest(energyAmount, unitPrice);

          const askReceipt = await askTx.wait();
          if (!askReceipt) throw new Error("Ask receipt missing");

          printEvents(askReceipt, energyContract);
        } catch (err: any) {
          console.error("Contract reverted");
          printReversion(err);
        }
        break;
      }
      case "roll": {
        await ethers.provider.send("evm_increaseTime", [bucketDuration]);
        await ethers.provider.send("evm_mine", []);

        try {
          const rollTx = await energyContract
            .connect(signers[account])
            .rollBucket();

          const rollReceipt = await rollTx.wait();
          if (!rollReceipt) throw new Error("Roll receipt missing");

          printEvents(rollReceipt, energyContract);
        } catch (err: any) {
          console.error("Contract reverted");
          printReversion(err);
        }
        break;
      }
      case "mark": {
        try {
          const energyAmount = BigInt(taskArgs.bucket);
          const unitPrice = BigInt(taskArgs.trade);

          const rollTx = await energyContract
            .connect(signers[account])
            .markEnergySupplied(energyAmount, unitPrice);

          const markReceipt = await rollTx.wait();
          if (!markReceipt) throw new Error("Mark receipt missing");

          printEvents(markReceipt, energyContract);
        } catch (err: any) {
          console.error("Contract reverted");
          printReversion(err);
        }
        break;
      }
      default: {
        console.log("Unrecognized command: ", cmd);
      }
    }
  });
