// scripts/deployFunctions.ts
import { ethers } from "hardhat";

const SUBSCRIPTION_ID = "5383"; // 替换成你的ID

async function main() {
  console.log("Deploying FunctionsConsumer...");
  const contract = await ethers.deployContract("FunctionsConsumer", [SUBSCRIPTION_ID]);
  await contract.waitForDeployment();
  console.log(`FunctionsConsumer deployed to: ${contract.target}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});