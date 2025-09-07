import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
  if (!CONTRACT_ADDRESS) {
    throw new Error("Please set CONTRACT_ADDRESS environment variable");
  }

  console.log("Deploying SchnorrK1Verifier...");
  
  // Deploy SchnorrK1Verifier
  const SchnorrK1Verifier = await ethers.getContractFactory("SchnorrK1Verifier");
  const schnorrVerifier = await SchnorrK1Verifier.deploy();
  await schnorrVerifier.waitForDeployment();
  const schnorrAddress = await schnorrVerifier.getAddress();
  
  console.log("SchnorrK1Verifier deployed to:", schnorrAddress);

  // Register with router
  console.log("Registering SchnorrK1Verifier with router...");
  const router = await ethers.getContractAt("UniversalOracleVerifier", CONTRACT_ADDRESS);
  const registerTx = await router.registerVerifier("schnorr-k1", schnorrAddress);
  await registerTx.wait();
  
  console.log("SchnorrK1Verifier registered successfully!");

  // Update addresses file
  let addresses: any = {};
  const addressFile = "addresses.sepolia.json";
  
  if (fs.existsSync(addressFile)) {
    addresses = JSON.parse(fs.readFileSync(addressFile, "utf8"));
  }
  
  if (!addresses.verifiers) addresses.verifiers = {};
  if (!addresses.history) addresses.history = {};
  
  // Update current address
  addresses.verifiers["schnorr-k1"] = schnorrAddress;
  
  // Add to history
  if (!addresses.history["schnorr-k1"]) {
    addresses.history["schnorr-k1"] = [];
  }
  addresses.history["schnorr-k1"].push(schnorrAddress);
  
  fs.writeFileSync(addressFile, JSON.stringify(addresses, null, 2));
  console.log("Address saved to", addressFile);

  // Verify registration
  const verifierAddress = await router.getVerifier("schnorr-k1");
  console.log("Verification - registered address:", verifierAddress);
  console.log("Match:", verifierAddress.toLowerCase() === schnorrAddress.toLowerCase());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
