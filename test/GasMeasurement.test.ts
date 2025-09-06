// test/GasMeasurement.test.ts
import { ethers } from "hardhat";

import { SimulatedOracle } from "../typechain-types/contracts/SimulatedOracle";
import { Signer } from "ethers";

describe("SimulatedOracle Gas Measurement", function () {
  
  async function deployOracle(nodeCount: number, requiredCount: number): Promise<{ oracle: SimulatedOracle, nodes: Signer[] }> {
    const signers = await ethers.getSigners();
    const nodes = signers.slice(1, nodeCount + 1);
    const nodeAddresses = nodes.map(node => node.address);
    
    const OracleFactory = await ethers.getContractFactory("SimulatedOracle");
    const oracle: SimulatedOracle = await OracleFactory.deploy(nodeAddresses, requiredCount);
    
    return { oracle, nodes };
  }

  async function measureGas(nodeCount: number, signatureCount: number, requiredCount: number) {
    const { oracle, nodes } = await deployOracle(nodeCount, requiredCount);
    
    const data = ethers.toUtf8Bytes(`DATA:${Date.now()}`);
    const messageHash = ethers.keccak256(data);
    
    const signatures = [];
    const signingNodes = nodes.slice(0, signatureCount);
    for (const node of signingNodes) {
      const signature = await node.signMessage(ethers.getBytes(messageHash));
      signatures.push(signature);
    }
    
    await oracle.fulfill(data, signatures);
  }

  it("Should run measurements and output gas report (up to 19 nodes)", async function () {
    console.log("Running Gas measurements...");
    
    // 这些测试场景都在19个节点的限制内
    await measureGas(5, 5, 3);
    await measureGas(10, 10, 7);
    await measureGas(15, 15, 10);
    await measureGas(19, 19, 15); // 将最大测试数量限制为19
  });
});