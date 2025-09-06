import fs from "fs";
import path from "path";
import { parseRunsFromExperimentFile } from "./utils/signatureUtils";

function main() {
  const txtPath = path.join(process.cwd(), "occlum", "experiment_data.txt");
  const jsonlPath = path.join(process.cwd(), "occlum", "experiment_data.jsonl");
  if (!fs.existsSync(txtPath)) {
    console.error("No occlum/experiment_data.txt found");
    process.exit(1);
  }
  const runs = parseRunsFromExperimentFile();
  if (runs.length === 0) {
    console.error("No runs matched by parser. Please check occlum/experiment_data.txt");
    process.exit(1);
  }
  const out = runs.map(r => JSON.stringify(r)).join("\n") + "\n";
  fs.writeFileSync(jsonlPath, out);
  console.log(`Wrote ${runs.length} runs to ${jsonlPath}`);
}

main();


