import { writeFileSync } from "fs";
import { task } from "hardhat/config";
import { resolve } from "path";

task(
  "deploy",
  "Deploys the EnergyTrade contract to the running Hardhat node",
).setAction(async () => {
  const { ethers } = require("hardhat");
  const [owner] = await ethers.getSigners();
  const bucketDuration = 900;
  const contractFactory = await ethers.getContractFactory("EnergyTrade", owner);
  const energyContract = await contractFactory.deploy(bucketDuration);
  await energyContract.waitForDeployment();
  const contractAddr = await energyContract.getAddress();
  console.log("`EnergyTrade` deployed to: ", contractAddr);

  const deployTx = energyContract.deploymentTransaction();
  if (!deployTx) throw new Error("Deployment transaction missing");

  const deployReceipt = await deployTx.wait();
  if (!deployReceipt) throw new Error("Deployment receipt missing");

  const contractInterface = contractFactory.interface;
  for (const log of deployReceipt.logs) {
    const parsedLog = contractInterface.parseLog(log);
    if (!parsedLog) throw new Error("Parsed log missing");

    if (parsedLog.name === "OwnerAnnounce")
      console.log("Owner address: ", parsedLog.args._ownerAddr);
  }

  writeFileSync(
    resolve(__dirname, "../deployed.json"),
    JSON.stringify({ contractAddr, bucketDuration }, null, 2),
  );
});
