import { ethers } from "hardhat";

async function main() {
  const routerAddress = process.env.CONTRACT_ADDRESS;
  if (!routerAddress) throw new Error("Set CONTRACT_ADDRESS (UniversalOracleVerifier)");

  const Router = await ethers.getContractAt("UniversalOracleVerifier", routerAddress);
  const V = await ethers.getContractFactory("R1Verifier");
  const v = await V.deploy();
  await v.waitForDeployment();
  const addr = await v.getAddress();
  console.log("R1Verifier deployed:", addr);

  const tx = await Router.registerVerifier("ecdsa-r1", addr);
  await tx.wait();
  console.log("Registered ecdsa-r1 ->", addr);
}

main().catch((e)=>{ console.error(e); process.exitCode=1; });
