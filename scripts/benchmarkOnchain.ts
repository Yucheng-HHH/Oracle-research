import { ethers } from "hardhat";
import { Interface } from "ethers";
import fs from "fs";
import { parseRunsPreferred, getSignatureRS, hexSizeBytes, RunEntry } from "./utils/signatureUtils";

const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "";
const COUNTS = (process.env.COUNTS || "5,10,15,20,25").split(",").map(s=>parseInt(s.trim(),10));
const OUT = process.env.OUT || `benchmark_universal.csv`;

const prepareSignatureData = (scheme: string, base64Sig: string, base64PubKey: string) => {
    let signatureBytes: Buffer;
    if (scheme === 'ed25519') {
      signatureBytes = Buffer.from(base64Sig, "base64");
    } else {
      const sig = getSignatureRS(base64Sig);
      signatureBytes = Buffer.concat([Buffer.from(sig.r.slice(2), 'hex'), Buffer.from(sig.s.slice(2), 'hex')]);
    }
    const prefixLength = scheme === 'ed25519' ? 12 : 27;
    const publicKeyBytes = Buffer.from(base64PubKey, 'base64').slice(prefixLength);
    return { signature: signatureBytes, publicKey: publicKeyBytes };
};

async function main() {
  if (!CONTRACT_ADDRESS) throw new Error("Set CONTRACT_ADDRESS");

  const allRuns = parseRunsPreferred();
  if (allRuns.length === 0) throw new Error("No runs found in occlum/experiment_data.jsonl");
  
  const verifier = await ethers.getContractAt("UniversalOracleVerifier", CONTRACT_ADDRESS);

  // Define the struct for the ABI
  const signatureDataStruct = "tuple(string data, bytes signature, bytes publicKey)";
  const iface = new Interface([
    `function verifyTwoSignatures(string scheme, ${signatureDataStruct} sigDataA, ${signatureDataStruct} sigDataB) public view returns(bool)`
  ]);
  const [signer] = await ethers.getSigners();

  const rows = ["count,scheme,avg_gas,calldata_bytes"];
  let offset = 0;

  for (const n of COUNTS) {
    if (offset >= allRuns.length) break;
    const group = allRuns.slice(offset, Math.min(offset + n, allRuns.length));
    offset += n;
    
    if(group.length === 0) continue;

    const scheme = group[0].scheme;
    const gasList: bigint[] = [];
    
    for (const r of group) {
      const tee = prepareSignatureData(r.scheme, r.deltaBase64Sig, r.deltaPublicKeyBase64);
      const ts = prepareSignatureData(r.scheme, r.sigmaBase64Sig, r.sigmaPublicKeyBase64);

      const sigDataA = { data: r.data, signature: tee.signature, publicKey: tee.publicKey };
      const sigDataB = { data: r.deltaPayload, signature: ts.signature, publicKey: ts.publicKey };

      const calldata = iface.encodeFunctionData("verifyTwoSignatures", [r.scheme, sigDataA, sigDataB]);

      const gas = await ethers.provider.estimateGas({
        from: await signer.getAddress(),
        to: CONTRACT_ADDRESS,
        data: calldata,
      });
      gasList.push(gas);
    }
    
    const avgGas = gasList.reduce((x,y)=>x+y, 0n) / BigInt(gasList.length);

    // Calculate calldata for a representative run
    const r0 = group[0];
    const tee0 = prepareSignatureData(r0.scheme, r0.deltaBase64Sig, r0.deltaPublicKeyBase64);
    const ts0  = prepareSignatureData(r0.scheme, r0.sigmaBase64Sig, r0.sigmaPublicKeyBase64);
    const calldata = iface.encodeFunctionData("verifyTwoSignatures", [
        r0.scheme,
        { data: r0.data, signature: tee0.signature, publicKey: tee0.publicKey },
        { data: r0.deltaPayload, signature: ts0.signature, publicKey: ts0.publicKey }
    ]);
    const calldataBytes = hexSizeBytes(calldata);

    rows.push(`${n},${scheme},${avgGas.toString()},${calldataBytes}`);
    console.log(`[${scheme}] count=${n} avg_gas=${avgGas.toString()} calldata_bytes=${calldataBytes}`);
  }

  fs.writeFileSync(OUT, rows.join("\n") + "\n");
  console.log("CSV written:", OUT);
}

main().catch((e)=>{ console.error(e); process.exitCode=1; });