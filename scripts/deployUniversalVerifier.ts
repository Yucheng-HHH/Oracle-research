import { ethers } from "hardhat";

async function main() {
  const RouterFactory = await ethers.getContractFactory("UniversalOracleVerifier");
  const router = await RouterFactory.deploy();
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log("UniversalOracleVerifier deployed:", routerAddr);

  const K1Factory = await ethers.getContractFactory("K1Verifier");
  const k1 = await K1Factory.deploy();
  await k1.waitForDeployment();
  const k1Addr = await k1.getAddress();
  console.log("K1Verifier deployed:", k1Addr);

  const tx = await router.registerVerifier("ecdsa-k1", k1Addr);
  await tx.wait();
  console.log("Registered ecdsa-k1 ->", k1Addr);
}

main().catch((e) => { console.error(e); process.exitCode = 1; });