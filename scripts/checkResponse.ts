// scripts/checkResponse.ts
import { ethers } from "hardhat";

const CONTRACT_ADDRESS = "0xFb6e8992003A7fa47fB8b67B57a119c900cc05aC"; // Your contract address

async function main() {
    const contract = await ethers.getContractAt("FunctionsConsumer", CONTRACT_ADDRESS);

    console.log("Checking for response from Chainlink Functions...");

    const latestResponse = await contract.latestResponse();
    const latestError = await contract.latestError();

    if (latestError.length > 0 && latestError !== "0x") {
        console.log(`\n❌ Error: ${ethers.toUtf8String(latestError)}`);
    }

    if (latestResponse.length > 0 && latestResponse !== "0x") {
        const btcPrice = ethers.toBigInt(latestResponse);
        console.log(`\n✅ Success! BTC Price: $${Number(btcPrice) / 100}`);
    }

    if (latestResponse.length <= 2 && latestError.length <= 2) {
         console.log("\nNo response yet. Please wait a few more minutes.");
    }
}

main().catch(e => console.error(e));