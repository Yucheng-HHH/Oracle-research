import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  console.log("Deploying OracleDataStorage contract...");
  
  const OracleDataStorage = await ethers.getContractFactory("OracleDataStorage");
  const oracleStorage = await OracleDataStorage.deploy();
  await oracleStorage.waitForDeployment();
  const address = await oracleStorage.getAddress();
  
  console.log("OracleDataStorage deployed to:", address);
  
  // Save address to file
  const deploymentInfo = {
    contract: "OracleDataStorage",
    address: address,
    network: "sepolia",
    deployedAt: new Date().toISOString(),
    deployer: (await ethers.getSigners())[0].address
  };
  
  fs.writeFileSync("oracle-storage-address.json", JSON.stringify(deploymentInfo, null, 2));
  console.log("Deployment info saved to oracle-storage-address.json");
  
  // Test basic functionality
  console.log("\nTesting basic functionality...");
  const testKey = ethers.keccak256(ethers.toUtf8Bytes("test-key"));
  const testData = ethers.toUtf8Bytes("Hello, Oracle World!");
  
  console.log("Writing test data...");
  const writeTx = await oracleStorage.writeData(testKey, testData);
  const writeReceipt = await writeTx.wait();
  console.log("Write transaction gas used:", writeReceipt.gasUsed.toString());
  
  console.log("Reading test data...");
  const [readData, readGas] = await oracleStorage.readData(testKey);
  console.log("Read data:", ethers.toUtf8String(readData));
  console.log("Read gas used:", readGas.toString());
  
  console.log("\nDeployment and testing completed successfully!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
