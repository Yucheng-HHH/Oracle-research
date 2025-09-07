import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
  if (!CONTRACT_ADDRESS) {
    throw new Error("Please set CONTRACT_ADDRESS environment variable");
  }

  console.log("Deploying Ed25519Verifier...");
  
  // Deploy Ed25519Verifier
  const Ed25519Verifier = await ethers.getContractFactory("Ed25519Verifier");
  const ed25519Verifier = await Ed25519Verifier.deploy();
  await ed25519Verifier.waitForDeployment();
  const ed25519Address = await ed25519Verifier.getAddress();
  
  console.log("Ed25519Verifier deployed to:", ed25519Address);

  // Register with router
  console.log("Registering Ed25519Verifier with router...");
  const router = await ethers.getContractAt("UniversalOracleVerifier", CONTRACT_ADDRESS);
  const registerTx = await router.registerVerifier("ed25519", ed25519Address);
  await registerTx.wait();
  
  console.log("Ed25519Verifier registered successfully!");

  // Update addresses file
  let addresses: any = {};
  const addressFile = "addresses.sepolia.json";
  
  if (fs.existsSync(addressFile)) {
    addresses = JSON.parse(fs.readFileSync(addressFile, "utf8"));
  }
  
  if (!addresses.verifiers) addresses.verifiers = {};
  if (!addresses.history) addresses.history = {};
  
  // Update current address
  addresses.verifiers["ed25519"] = ed25519Address;
  
  // Add to history
  if (!addresses.history["ed25519"]) {
    addresses.history["ed25519"] = [];
  }
  addresses.history["ed25519"].push(ed25519Address);
  
  fs.writeFileSync(addressFile, JSON.stringify(addresses, null, 2));
  console.log("Address saved to", addressFile);

  // Verify registration
  const verifierAddress = await router.getVerifier("ed25519");
  console.log("Verification - registered address:", verifierAddress);
  console.log("Match:", verifierAddress.toLowerCase() === ed25519Address.toLowerCase());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
