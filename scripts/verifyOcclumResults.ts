import { ethers } from "hardhat";
import { parseRunsPreferred, getSignatureRS } from "./utils/signatureUtils";

const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "";

async function main() {
  if (!CONTRACT_ADDRESS) throw new Error("Set CONTRACT_ADDRESS in your environment");

  const runs = parseRunsPreferred();
  if (runs.length === 0) throw new Error("No runs found in occlum/experiment_data.jsonl");
  const lastRun = runs[runs.length - 1];

  console.log(`Verifying last run with scheme: ${lastRun.scheme}`);
  
  const verifier = await ethers.getContractAt("UniversalOracleVerifier", CONTRACT_ADDRESS);

  // Helper function to prepare data for the contract
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

  const tee = prepareSignatureData(lastRun.scheme, lastRun.deltaBase64Sig, lastRun.deltaPublicKeyBase64);
  const ts = prepareSignatureData(lastRun.scheme, lastRun.sigmaBase64Sig, lastRun.sigmaPublicKeyBase64);
  
  // Create struct objects for the contract call
  const sigDataA = {
    data: lastRun.data,
    signature: tee.signature,
    publicKey: tee.publicKey
  };

  const sigDataB = {
    data: lastRun.deltaPayload,
    signature: ts.signature,
    publicKey: ts.publicKey
  };

  // Call the refactored verification function
  const isValid = await verifier.verifyTwoSignatures(
    lastRun.scheme,
    sigDataA,
    sigDataB
  );

  console.log(`Verification successful: ${isValid}`);
  if (!isValid) {
      console.error("Verification failed!");
      process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});