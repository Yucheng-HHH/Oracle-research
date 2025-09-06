import { ethers } from "hardhat";
import { parseRunsPreferred, base64DerToRSVAndAddressSha256 } from "./utils/signatureUtils";

const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "";

async function main() {
  if (!CONTRACT_ADDRESS) throw new Error("Set CONTRACT_ADDRESS");

  // Use the latest run from experiment_data.txt (TEE + TS)
  const runs = parseRunsPreferred();
  if (runs.length === 0) throw new Error("No runs parsed from occlum/experiment_data.txt");
  const r = runs[runs.length - 1];
  const tee = base64DerToRSVAndAddressSha256(r.deltaBase64Sig, r.data);
  const ts  = base64DerToRSVAndAddressSha256(r.sigmaBase64Sig, r.deltaPayload);

  console.log("Recovered TEE:", tee.addr);
  console.log("Recovered TS:", ts.addr);

  const verifier = await ethers.getContractAt("OracleVerifier", CONTRACT_ADDRESS);
  // Prefer SHA256 path if your TEE used SHA256 without eth-prefix
  const ok = await (verifier as any).verifyTwoSignaturesSha256(
    r.data, ethers.getBytes(tee.rsv), tee.addr,
    r.deltaPayload, ethers.getBytes(ts.rsv), ts.addr
  );
  console.log("verifyTwoSignaturesSha256:", ok);
}

main().catch((e)=>{ console.error(e); process.exitCode=1; });