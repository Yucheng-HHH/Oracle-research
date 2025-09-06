// scripts/makeFunctionsRequest.ts
import { ethers } from "hardhat";

// 1. 从 Hardhat 自动生成的类型文件夹中导入你的合约类型
import { FunctionsConsumer } from "../typechain-types";

// 确保这里是你部署后的合约地址
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "";

async function main() {
    console.log("Getting the contract factory...");
    const ContractFactory = await ethers.getContractFactory("FunctionsConsumer");
    
    console.log("Attaching to deployed contract at", CONTRACT_ADDRESS);

    // 2. 在这里，我们将 'contract' 变量的类型显式声明为 FunctionsConsumer
    //    这样 TypeScript 就知道它有哪些函数和变量了
    const contract: FunctionsConsumer = ContractFactory.attach(CONTRACT_ADDRESS) as FunctionsConsumer;

    console.log("Sending Chainlink Functions request...");
    const tx = await contract.sendRequest();
    await tx.wait();

    // 现在 TypeScript 知道 contract.latestRequestId 是存在的，错误消失
    const requestId = await contract.latestRequestId();
    console.log(`Request sent! Request ID: ${requestId}`);
    console.log("Wait a few minutes for the DON to fulfill the request.");
}

main().catch((e) => {
    console.error(e);
    process.exitCode = 1;
});