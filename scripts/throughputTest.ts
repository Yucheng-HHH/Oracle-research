// scripts/throughputTest.ts
import { ethers } from "hardhat";
import { SimulatedOracle } from "../typechain-types/contracts/SimulatedOracle";
import { Signer } from "ethers";

// --- 配置常量 ---
// Hardhat本地网络的默认区块Gas上限
const BLOCK_GAS_LIMIT = 30_000_000; 
// 以太坊主网的平均出块时间（秒），用于标准化TPS结果
const AVG_BLOCK_TIME_SECONDS = 12; 

// --- 测试参数 ---
// 我们将基于一个有19个节点，要求15个签名的场景来计算
const NODE_COUNT = 19;
const SIGNATURE_COUNT = 19;
const REQUIRED_SIGNATURES = 15;

async function deployOracle(nodeCount: number, requiredCount: number): Promise<{ oracle: SimulatedOracle, nodes: Signer[] }> {
    const signers = await ethers.getSigners();
    const nodes = signers.slice(1, nodeCount + 1);
    const nodeAddresses = nodes.map(node => node.address);
    
    const OracleFactory = await ethers.getContractFactory("SimulatedOracle");
    const oracle: SimulatedOracle = await OracleFactory.deploy(nodeAddresses, requiredCount);
    await oracle.waitForDeployment();
    return { oracle, nodes };
}

async function main() {
    console.log("🚀 开始估算吞吐率...");
    console.log("----------------------------------------------------");
    console.log(`测试场景: ${NODE_COUNT}个节点, ${REQUIRED_SIGNATURES}个签名阈值。`);
    console.log("正在部署合约并发送单笔交易以测量Gas消耗...");

    const { oracle, nodes } = await deployOracle(NODE_COUNT, REQUIRED_SIGNATURES);
    
    const data = ethers.toUtf8Bytes(`THROUGHPUT_TEST:${Date.now()}`);
    const messageHash = ethers.keccak256(data);
    
    const signatures = [];
    const signingNodes = nodes.slice(0, SIGNATURE_COUNT);
    for (const node of signingNodes) {
      const signature = await node.signMessage(ethers.getBytes(messageHash));
      signatures.push(signature);
    }
    
    const tx = await oracle.fulfill(data, signatures);
    const receipt = await tx.wait();
    const singleTxGas = receipt?.gasUsed ?? 0n;

    if (singleTxGas === 0n) {
        console.error("❌ 无法获取交易的Gas消耗，脚本终止。");
        return;
    }

    // --- 开始计算 ---
    const maxTxPerBlock = BLOCK_GAS_LIMIT / Number(singleTxGas);
    const theoreticalTPS = maxTxPerBlock / AVG_BLOCK_TIME_SECONDS;

    // --- 打印结果 ---
    console.log("\n✅ 计算完成!");
    console.log("----------------------------------------------------");
    console.log(`单笔 fulfill 交易的Gas消耗: ${singleTxGas.toString()}`);
    console.log(`Hardhat区块Gas上限:         ${BLOCK_GAS_LIMIT.toLocaleString()}`);
    console.log(`以太坊平均出块时间:         ${AVG_BLOCK_TIME_SECONDS} 秒`);
    console.log("----------------------------------------------------");
    console.log(`每个区块理论上可容纳交易数: ≈ ${maxTxPerBlock.toFixed(2)} 笔`);
    console.log(`标准化理论吞吐率 (TPS):     ≈ ${theoreticalTPS.toFixed(2)} 笔/秒`);
    console.log("----------------------------------------------------");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
