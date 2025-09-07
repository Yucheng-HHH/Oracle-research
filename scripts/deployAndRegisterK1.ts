import { ethers } from "hardhat";

async function main() {
  const routerAddress = process.env.CONTRACT_ADDRESS;
  if (!routerAddress) throw new Error("Set CONTRACT_ADDRESS to UniversalOracleVerifier address");

  const Router = await ethers.getContractAt("UniversalOracleVerifier", routerAddress);

  const K1 = await ethers.getContractFactory("K1Verifier");
  const k1 = await K1.deploy();
  await k1.waitForDeployment();
  const k1Addr = await k1.getAddress();
  console.log("K1Verifier deployed:", k1Addr);

  const tx = await Router.registerVerifier("ecdsa-k1", k1Addr);
  await tx.wait();
  console.log("Registered ecdsa-k1 ->", k1Addr);
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
