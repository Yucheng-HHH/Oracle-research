import { ethers } from "hardhat";

async function main() {
  const Factory = await ethers.getContractFactory("OracleVerifier");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();
  console.log("OracleVerifier deployed at:", await contract.getAddress());
}

main().catch((e) => { console.error(e); process.exitCode = 1; });