import { ethers } from "hardhat";
import { Interface } from "ethers";
import fs from "fs";
import { parseRunsPreferred, base64DerToRSVAndAddressSha256, hexSizeBytes } from "./utils/signatureUtils";

const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "";
const COUNTS = (process.env.COUNTS || "5,10,15,20,25").split(",").map(s=>parseInt(s.trim(),10));
const MODE = (process.env.MODE || "two") as "one"|"two"; // "one" 单签; "two" 双签
const OUT = process.env.OUT || `benchmark_${MODE}.csv`;

async function main() {
  if (!CONTRACT_ADDRESS) throw new Error("Set CONTRACT_ADDRESS");

  const runs = parseRunsPreferred();

  const verifier = await ethers.getContractAt("OracleVerifier", CONTRACT_ADDRESS);
  const iface = new Interface([
    "function verifySignature(string data, bytes signature, address expectedSigner) public pure returns(bool)",
    "function verifyTwoSignatures(string dataA, bytes signatureA, address expectedSignerA, string dataB, bytes signatureB, address expectedSignerB) public pure returns(bool)",
    "function verifySignatureSha256(string data, bytes signature, address expectedSigner) public pure returns(bool)",
    "function verifyTwoSignaturesSha256(string dataA, bytes signatureA, address expectedSignerA, string dataB, bytes signatureB, address expectedSignerB) public pure returns(bool)"
  ]);
  const [signer] = await ethers.getSigners();

  const rows = ["count,avg_gas,calldata_bytes"];
  let offset = 0;
  for (const n of COUNTS) {
    const gasList: bigint[] = [];
    const group = runs.slice(offset, Math.min(offset + n, runs.length));
    offset += n;
    for (let i=0;i<n;i++) {
      const r = group[i] ?? runs[runs.length - 1];
      const tee = base64DerToRSVAndAddressSha256(r.deltaBase64Sig, r.data);
      const ts  = base64DerToRSVAndAddressSha256(r.sigmaBase64Sig, r.deltaPayload);

      const calldata = MODE === "one"
        ? iface.encodeFunctionData("verifySignatureSha256", [r.data, ethers.getBytes(tee.rsv), tee.addr])
        : iface.encodeFunctionData("verifyTwoSignaturesSha256", [r.data, ethers.getBytes(tee.rsv), tee.addr, r.deltaPayload, ethers.getBytes(ts.rsv), ts.addr]);

      const gas = await ethers.provider.estimateGas({
        from: await signer.getAddress(),
        to: CONTRACT_ADDRESS,
        data: calldata,
      });
      gasList.push(gas);
    }
    const avgGas = gasList.reduce((x,y)=>x+y, 0n) / BigInt(gasList.length);

    const r0 = group[0] ?? runs[0];
    const tee0 = base64DerToRSVAndAddressSha256(r0.deltaBase64Sig, r0.data);
    const ts0  = base64DerToRSVAndAddressSha256(r0.sigmaBase64Sig, r0.deltaPayload);
    const calldata = MODE === "one"
      ? iface.encodeFunctionData("verifySignatureSha256", [r0.data, ethers.getBytes(tee0.rsv), tee0.addr])
      : iface.encodeFunctionData("verifyTwoSignaturesSha256", [r0.data, ethers.getBytes(tee0.rsv), tee0.addr, r0.deltaPayload, ethers.getBytes(ts0.rsv), ts0.addr]);

    const calldataBytes = hexSizeBytes(calldata);

    rows.push(`${n},${avgGas.toString()},${calldataBytes}`);
    console.log(`[${MODE}] count=${n} avg_gas=${avgGas.toString()} calldata_bytes=${calldataBytes}`);
  }

  fs.writeFileSync(OUT, rows.join("\n"));
  console.log("CSV written:", OUT);
}

main().catch((e)=>{ console.error(e); process.exitCode=1; });