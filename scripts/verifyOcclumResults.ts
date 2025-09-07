import { ethers } from "hardhat";
import { parseRunsPreferred, getSignatureRS } from "./utils/signatureUtils";

const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "";

async function main() {
  if (!CONTRACT_ADDRESS) throw new Error("Set CONTRACT_ADDRESS in your environment");

  const runs = parseRunsPreferred();
  if (runs.length === 0) throw new Error("No runs found in occlum/experiment_data.jsonl");
  const lastRun = runs[runs.length - 1];

  console.log(`Verifying last run with scheme: ${lastRun.scheme}`);

  // Ed25519 is now supported via pure Solidity implementation
  // Note: Ed25519 verification is computationally expensive but works for research purposes
  
  const verifier = await ethers.getContractAt("UniversalOracleVerifier", CONTRACT_ADDRESS);

  // 公钥解析：兼容 SPKI、未压缩(0x04||X||Y)、裸 X||Y
  const findUncompressedKeyInSpki = (spki: Buffer): number => {
    // 寻找 0x03, <len>, 0x00, 0x04 的模式，返回 0x04 的位置
    for (let i = 0; i < spki.length - 3; i++) {
      if (spki[i] === 0x03 && spki[i + 2] === 0x00 && spki[i + 3] === 0x04) return i + 3;
    }
    return -1;
  };

  const parsePublicKey = (scheme: string, base64PubKey: string): Buffer => {
    const raw = Buffer.from(base64PubKey, 'base64');
    if (scheme === 'ed25519') {
      // RFC 8410: SPKI 12 字节前缀 + 32 字节公钥；为鲁棒起见取末尾 32 字节
      if (raw.length >= 32) return raw.slice(raw.length - 32);
      throw new Error('Invalid ed25519 public key');
    }
    // ecdsa-k1/r1：接受 64(裸 X||Y)、65(0x04||X||Y)、SPKI
    if (raw.length === 64) return raw;
    if (raw.length === 65 && raw[0] === 0x04) return raw.slice(1);
    const idx = findUncompressedKeyInSpki(raw);
    if (idx >= 0 && raw.length >= idx + 1 + 64) return raw.slice(idx + 1, idx + 1 + 64);
    // 退而求其次：历史上常见的 27 字节前缀切片（非标准，尽量避免）
    if (raw.length >= 27 + 64) return raw.slice(27, 27 + 64);
    throw new Error('Invalid ECDSA public key encoding');
  };

  // Helper function to prepare data for the contract
  const prepareSignatureData = (scheme: string, base64Sig: string, base64PubKey: string) => {
    let signatureBytes: Buffer;
    if (scheme === 'ed25519') {
      signatureBytes = Buffer.from(base64Sig, "base64");
    } else {
      const sig = getSignatureRS(base64Sig);
      signatureBytes = Buffer.concat([Buffer.from(sig.r.slice(2), 'hex'), Buffer.from(sig.s.slice(2), 'hex')]);
    }

    const publicKeyBytes = parsePublicKey(scheme, base64PubKey);

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