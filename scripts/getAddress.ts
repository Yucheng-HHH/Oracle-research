// scripts/getAddress.ts
import { ethers } from "hardhat";
import "dotenv/config";

async function main() {
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("PRIVATE_KEY not set in .env file");
  }
  const wallet = new ethers.Wallet(privateKey);
  console.log("Your wallet address is:", wallet.address);
}

main();