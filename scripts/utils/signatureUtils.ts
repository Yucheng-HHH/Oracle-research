import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

// New RunEntry type that includes public keys
export type RunEntry = {
  scheme: string;
  data: string;
  deltaPayload: string;
  deltaBase64Sig: string;
  sigmaBase64Sig: string;
  deltaPublicKeyBase64: string;
  sigmaPublicKeyBase64: string;
};

// Updated parser for the new JSONL format
export function parseRunsFromJsonl(): RunEntry[] {
  const filePath = path.join(process.cwd(), "occlum", "experiment_data.jsonl");
  if (!fs.existsSync(filePath)) {
      console.error(`Error: File not found at ${filePath}`);
      return [];
  }
  
  const fileContent = fs.readFileSync(filePath, "utf8");
  if (!fileContent.trim()) {
      console.error(`Error: File at ${filePath} is empty.`);
      return [];
  }

  const lines = fileContent.split(/\r?\n/).filter(line => line.trim() !== "");
  const runs: RunEntry[] = [];
  
  for (const line of lines) {
    try {
      const obj = JSON.parse(line);
      // Ensure all new fields are present
      if (obj.scheme && obj.data && obj.deltaPayload && obj.deltaBase64Sig && obj.sigmaBase64Sig && obj.deltaPublicKeyBase64 && obj.sigmaPublicKeyBase64) {
        runs.push(obj);
      } else {
        console.warn("Skipping a malformed line in JSONL:", line);
      }
    } catch (e) { 
        console.error("Skipping a line that failed to parse in JSONL:", line, e);
    }
  }
  return runs;
}

export function parseRunsPreferred(): RunEntry[] {
  return parseRunsFromJsonl();
}

function derToRS(der: Uint8Array): { r: string; s: string } {
  let i = 0;
  if (der[i++] !== 0x30) throw new Error("Invalid DER sequence");
  let seqLen = der[i++];
  if (seqLen > der.length - i) seqLen = der.length - i; // Be lenient with length

  if (der[i++] !== 0x02) throw new Error("Expected DER integer for r");
  const rLen = der[i++]; let r = der.slice(i, i + rLen); i += rLen;
  
  if (der[i++] !== 0x02) throw new Error("Expected DER integer for s");
  const sLen = der[i++]; let s = der.slice(i, i + sLen);

  const strip = (b: Uint8Array) => { let j=0; while (j<b.length - 1 && b[j]===0x00) j++; return b.slice(j); };
  const pad32 = (b: Uint8Array) => { 
      const stripped = strip(b);
      if (stripped.length > 32) throw new Error(`Value too long: ${Buffer.from(stripped).toString('hex')}`);
      const out=new Uint8Array(32); 
      out.set(stripped, 32-stripped.length); 
      return out; 
  };

  return {
    r: "0x"+Buffer.from(pad32(r)).toString("hex"),
    s: "0x"+Buffer.from(pad32(s)).toString("hex"),
  };
}

export function getSignatureRS(base64Sig: string): { r: string; s: string } {
    const der = Buffer.from(base64Sig, "base64");
    return derToRS(new Uint8Array(der));
}

export function hexSizeBytes(hex: string): number {
  return (hex.startsWith("0x") ? (hex.length - 2) : hex.length) / 2;
}