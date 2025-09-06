import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

export type Pair = { data: string; base64Sig: string };

export function parseExperimentFile(): { A: Pair; B: Pair } {
  const filePath = path.join(process.cwd(), "occlum", "experiment_data.txt");
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/).map(s => s.trim());

  const iA = lines.findIndex(l => l.includes("Oracle A"));
  const iB = lines.findIndex(l => l.includes("Oracle B"));
  const blkA = lines.slice(iA, iB);
  const blkB = lines.slice(iB);

  const dataA = blkA.find(l => l.startsWith("PageRank Result String:"))!.split(":")[1].trim().replace(/^ /, "");
  const sigA  = blkA.find(l => l.startsWith("TEE Signature (Base64):"))!.split(":")[1].trim().replace(/^ /, "");
  const dataB = blkB.find(l => l.startsWith("PageRank Result String:"))!.split(":")[1].trim().replace(/^ /, "");
  const sigB  = blkB.find(l => l.startsWith("TEE Signature (Base64):"))!.split(":")[1].trim().replace(/^ /, "");
  return { A: { data: dataA, base64Sig: sigA }, B: { data: dataB, base64Sig: sigB } };
}

// -------- New parsing for TEE + TimeServer runs --------
export type RunEntry = {
  data: string;                        // PageRank Result String
  // Unified (preferred) fields for chained scheme
  deltaPayload: string;                // TSv1|sha256(data)|sha256(deltaSigDER)|timestamp
  deltaBase64Sig: string;              // TEE signature over data (Base64 DER)
  sigmaBase64Sig: string;              // TS signature over deltaPayload (Base64 DER)
  // Legacy fields (optional). If present, we will map them to the unified fields.
  teeBase64Sig?: string;
  tsPayload?: string;
  tsBase64Sig?: string;
};

export function parseRunsFromJsonl(): RunEntry[] {
  const filePath = path.join(process.cwd(), "occlum", "experiment_data.jsonl");
  if (!fs.existsSync(filePath)) return [];
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/).filter(Boolean);
  const runs: RunEntry[] = [];
  for (const line of lines) {
    try {
      const obj = JSON.parse(line);
      const { data } = obj || {};
      if (!data) continue;
      // Prefer chained fields
      if (obj.deltaPayload && obj.deltaBase64Sig && obj.sigmaBase64Sig) {
        runs.push({
          data,
          deltaPayload: obj.deltaPayload,
          deltaBase64Sig: obj.deltaBase64Sig,
          sigmaBase64Sig: obj.sigmaBase64Sig,
        });
        continue;
      }
      // Map legacy to chained
      if (obj.teeBase64Sig && obj.tsPayload && obj.tsBase64Sig) {
        runs.push({
          data,
          deltaPayload: obj.tsPayload,
          deltaBase64Sig: obj.teeBase64Sig,
          sigmaBase64Sig: obj.tsBase64Sig,
          teeBase64Sig: obj.teeBase64Sig,
          tsPayload: obj.tsPayload,
          tsBase64Sig: obj.tsBase64Sig,
        });
      }
    } catch (_) { /* skip bad lines */ }
  }
  return runs;
}

export function parseRunsFromExperimentFile(): RunEntry[] {
  const filePath = path.join(process.cwd(), "occlum", "experiment_data.txt");
  const text = fs.readFileSync(filePath, "utf8");
  const runs: RunEntry[] = [];
  const re = /PageRank\s+Result\s+String:\s*([^\r\n]+)\r?\n(?:TEE|Delta)\s+Signature\s*\(Base64\):\s*([^\r\n]*)\r?\n(?:TimeServer\s+Payload|Delta\s+Payload):\s*([^\r\n]*)\r?\n(?:TimeServer|Sigma)\s+Signature\s*\(Base64\):\s*([^\r\n]*)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const data = m[1].trim();
    const legacyTee = m[2].trim();
    const payload = m[3].trim();
    const legacyTs = m[4].trim();
    runs.push({
      data,
      deltaPayload: payload,
      deltaBase64Sig: legacyTee,
      sigmaBase64Sig: legacyTs,
      teeBase64Sig: legacyTee,
      tsPayload: payload,
      tsBase64Sig: legacyTs,
    });
  }
  return runs;
}

export function parseRunsPreferred(): RunEntry[] {
  const jsonl = parseRunsFromJsonl();
  if (jsonl.length > 0) return jsonl;
  return parseRunsFromExperimentFile();
}

function derToRS(der: Uint8Array): { r: string; s: string } {
  let i = 0;
  if (der[i++] !== 0x30) throw new Error("Invalid DER");
  i++; // seq len
  if (der[i++] !== 0x02) throw new Error("Invalid DER");
  const rLen = der[i++]; let r = der.slice(i, i + rLen); i += rLen;
  if (der[i++] !== 0x02) throw new Error("Invalid DER");
  const sLen = der[i++]; let s = der.slice(i, i + sLen);

  const strip = (b: Uint8Array) => { let j=0; while (j<b.length && b[j]===0x00) j++; return b.slice(j); };
  const pad32 = (b: Uint8Array) => { const t = strip(b); if (t.length>32) throw new Error("too long"); const out=new Uint8Array(32); out.set(t, 32-t.length); return out; };

  return {
    r: "0x"+Buffer.from(pad32(r)).toString("hex"),
    s: "0x"+Buffer.from(pad32(s)).toString("hex"),
  };
}

export function dataHash(data: string): string {
  const m = ethers.keccak256(ethers.toUtf8Bytes(data));
  return ethers.hashMessage(ethers.getBytes(m)); // "\x19Ethereum Signed Message:\n32" + m
}

export function dataHashSha256(data: string): string {
  return ethers.sha256(ethers.toUtf8Bytes(data));
}

export function base64DerToRSVAndAddress(base64Sig: string, data: string) {
    const secpN = BigInt("0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141");
    const secpHalfN = secpN >> 1n;
  
    const der = Buffer.from(base64Sig, "base64");
    const { r, s } = derToRS(new Uint8Array(der));
  
    // 低 s 规范化
    let sBI = BigInt(s);
    if (sBI > secpHalfN) {
      sBI = secpN - sBI;
    }
    const sCanon = "0x" + sBI.toString(16).padStart(64, "0");
  
    const hash = dataHash(data); // 仍使用 ethSignedMessage(keccak256(data))
  
    // 尝试 v=27/28，找到可恢复的地址
    for (const v of [27, 28] as const) {
      const addr = ethers.recoverAddress(hash, { r, s: sCanon, v });
      if (ethers.isAddress(addr)) {
        const rsv = ethers.Signature.from({ r, s: sCanon, v }).serialized;
        return { rsv, addr };
      }
    }
    throw new Error("cannot determine v");
  }
  
export function hexSizeBytes(hex: string): number {
  return (hex.startsWith("0x") ? (hex.length - 2) : hex.length) / 2;
}

export function base64DerToRSVAndAddressSha256(base64Sig: string, data: string) {
  const secpN = BigInt("0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141");
  const secpHalfN = secpN >> 1n;

  const der = Buffer.from(base64Sig, "base64");
  const { r, s } = derToRS(new Uint8Array(der));

  let sBI = BigInt(s);
  if (sBI > secpHalfN) sBI = secpN - sBI;
  const sCanon = "0x" + sBI.toString(16).padStart(64, "0");

  const digest = dataHashSha256(data);
  for (const v of [27, 28] as const) {
    const addr = ethers.recoverAddress(digest, { r, s: sCanon, v });
    if (ethers.isAddress(addr)) {
      const rsv = ethers.Signature.from({ r, s: sCanon, v }).serialized;
      return { rsv, addr };
    }
  }
  throw new Error("cannot determine v");
}