#!/bin/bash
# This script automates the entire process of compiling, packaging, and running
# a multi-file Java application inside an Occlum SGX enclave.
set -e

# --- Configuration ---
BLUE='\033[1;34m'
NC='\033[0m'
PROJECT_DIR="pagerank_project"
JAR_NAME="pagerank.jar"

# --- Set Environment Variables for Occlum Toolchain ---
# This points to the specific library paths required by Occlum's toolchain.
export JAVA_HOME=/opt/occlum/toolchains/jvm/java-11-alibaba-dragonwell
export PATH=$JAVA_HOME/bin:$PATH
export LD_LIBRARY_PATH=/opt/occlum/toolchains/gcc/x86_64-linux-musl/lib

echo -e "${BLUE}Step 1: Compiling Java source and creating executable JAR file...${NC}"
# --- Clean and Compile ---
rm -rf ${PROJECT_DIR}/classes && mkdir -p ${PROJECT_DIR}/classes
occlum-javac -d ./${PROJECT_DIR}/classes ./${PROJECT_DIR}/src/com/mypagerank/*.java

# --- Package into JAR ---
jar cvfm ${JAR_NAME} ./${PROJECT_DIR}/manifest.txt -C ./${PROJECT_DIR}/classes .
echo "Successfully created ${JAR_NAME}"
echo ""


echo -e "${BLUE}Step 2: Initializing clean Occlum instance...${NC}"
# --- Init Occlum ---
rm -rf occlum_instance && mkdir occlum_instance
cd occlum_instance
occlum init

# --- Configure Occlum via jq ---
# This configuration is based on the official Occlum Java demos.
new_json="$(jq '.resource_limits.user_space_max_size = "1680MB" |
            .process.default_heap_size = "256MB" |
            .entry_points = [ "/usr/lib/jvm/java-11-alibaba-dragonwell/jre/bin" ] |
            .env.default = [ "LD_LIBRARY_PATH=/usr/lib/jvm/java-11-alibaba-dragonwell/jre/lib/server:/usr/lib/jvm/java-11-alibaba-dragonwell/jre/lib:/usr/lib/jvm/java-11-alibaba-dragonwell/jre/../lib" ]' Occlum.json)" && \
echo "${new_json}" > Occlum.json
echo "Occlum instance configured."
echo ""


echo -e "${BLUE}Step 3: Building Occlum secure image...${NC}"
# --- Build Image ---
rm -rf image
copy_bom -f ../${PROJECT_DIR}/pagerank.yaml --root image --include-dir /opt/occlum/etc/template
occlum build --sgx-mode SIM
echo "Occlum image built."
echo ""


echo -e "${BLUE}Step 4: Running PageRank application inside Occlum...${NC}"

# Helper to run once and emit a CSV metrics line (without header)
run_once() {
  local out
  out=$(occlum run /usr/lib/jvm/java-11-alibaba-dragonwell/jre/bin/java -Xmx512m -XX:MaxMetaspaceSize=64m -jar /app/${JAR_NAME})
  echo "$out"

  # Optionally save artifacts for on-chain input (JSONL with delta/sigma)
  save_artifacts() {
    local text="$1"
    local rs=$(echo "$text" | sed -n 's/^PageRank Result String:[[:space:]]*\(.*\)$/\1/p' | head -n1)
    local delta_payload=$(echo "$text" | sed -n 's/^Delta Payload:[[:space:]]*\(.*\)$/\1/p' | head -n1)
    local delta_sig=$(echo "$text" | sed -n 's/^Delta Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1)
    local sigma_sig=$(echo "$text" | sed -n 's/^Sigma Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1)

    # Append machine-readable JSONL for chain input
    local JSONL="../experiment_data.jsonl"
    if [ -n "$rs" ] && [ -n "$delta_payload" ] && [ -n "$delta_sig" ] && [ -n "$sigma_sig" ]; then
      printf '{"data":"%s","deltaPayload":"%s","deltaBase64Sig":"%s","sigmaBase64Sig":"%s"}\n' \
        "$rs" "$delta_payload" "$delta_sig" "$sigma_sig" >> "$JSONL"
      echo "Artifacts appended to $JSONL"
    else
      echo "WARN: Missing one of required fields (data/delta/sigma); skipping JSONL append" >&2
    fi
  }

  if [ "${SAVE_ARTIFACTS:-1}" -eq 1 ]; then
    save_artifacts "$out"
  fi

  # Extract metrics
  local pr=$(echo "$out" | grep -oE "PR_compute_ms:[0-9]+" | cut -d: -f2)
  local tee_s=$(echo "$out" | grep -oE "Sign_ms:[0-9]+" | cut -d: -f2)
  local ts_s=$(echo "$out" | grep -oE "TS_Sign_ms:[0-9]+" | cut -d: -f2)
  local ts_v=$(echo "$out" | grep -oE "TS_Verify_ms:[0-9]+" | cut -d: -f2)
  # Robust extraction (tolerate spaces): use sed anchored at line start
  # New metrics for chained scheme (base64 sizes only as required)
  local delta_ms=$(echo "$out" | sed -n 's/^Delta_Sign_ms:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local dver_ms=$(echo "$out" | sed -n 's/^Delta_Verify_ms:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local sigma_ms=$(echo "$out" | sed -n 's/^Sigma_Sign_ms:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local sver_ms=$(echo "$out" | sed -n 's/^Sigma_Verify_ms:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local delta_b64=$(echo "$out" | sed -n 's/^Delta_Sig_base64_bytes:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local sigma_b64=$(echo "$out" | sed -n 's/^Sigma_Sig_base64_bytes:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  # robust fallback: compute from inline base64 lines
  if [ -z "$delta_b64" ]; then delta_b64=$(echo "$out" | sed -n 's/^Delta Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1 | wc -c); fi
  if [ -z "$sigma_b64" ]; then sigma_b64=$(echo "$out" | sed -n 's/^Sigma Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1 | wc -c); fi

  # Emit one CSV record values (without count)
  echo "$delta_ms,$dver_ms,$sigma_ms,$sver_ms,$delta_b64,$sigma_b64"
}

# Prepare CSV under project root
CSV_PATH="../tee_benchmark_coarse.csv"
if [ ! -f "$CSV_PATH" ]; then
  echo "count,Delta_Sign_ms,Delta_Verify_ms,Sigma_Sign_ms,Sigma_Verify_ms,Delta_Sig_base64_bytes,Sigma_Sig_base64_bytes" > "$CSV_PATH"
fi

# Support RUNS (single value) or RUNS_LIST (comma list like 5,10,15,20,25)
if [ -n "$RUNS_LIST" ]; then
  IFS=',' read -ra RUN_LIST_ARR <<< "$RUNS_LIST"
  for RUNS in "${RUN_LIST_ARR[@]}"; do
    total_delta=0; total_dver=0; total_sigma=0; total_sver=0; last_delta_b64=0; last_sigma_b64=0

    for i in $(seq 1 "$RUNS"); do
      rec=$(run_once | tail -n1)
      delta=$(echo "$rec" | cut -d, -f1)
      dver=$(echo "$rec" | cut -d, -f2)
      sigma=$(echo "$rec" | cut -d, -f3)
      sver=$(echo "$rec" | cut -d, -f4)
      delta_b64=$(echo "$rec" | cut -d, -f5)
      sigma_b64=$(echo "$rec" | cut -d, -f6)

      total_delta=$(( total_delta + ${delta:-0} ))
      total_dver=$(( total_dver + ${dver:-0} ))
      total_sigma=$(( total_sigma + ${sigma:-0} ))
      total_sver=$(( total_sver + ${sver:-0} ))
      last_delta_b64=$delta_b64; last_sigma_b64=$sigma_b64
    done

    avg_delta=$(( total_delta / RUNS ))
    avg_dver=$(( total_dver / RUNS ))
    avg_sigma=$(( total_sigma / RUNS ))
    avg_sver=$(( total_sver / RUNS ))
    echo "$RUNS,$avg_delta,$avg_dver,$avg_sigma,$avg_sver,${last_delta_b64:-0},${last_sigma_b64:-0}" >> "$CSV_PATH"
  done
else
  # Single RUN (or default 1)
  RUNS=${RUNS:-1}
  total_delta=0; total_dver=0; total_sigma=0; total_sver=0; last_delta_b64=0; last_sigma_b64=0
  for i in $(seq 1 "$RUNS"); do
    rec=$(run_once | tail -n1)
    delta=$(echo "$rec" | cut -d, -f1)
    dver=$(echo "$rec" | cut -d, -f2)
    sigma=$(echo "$rec" | cut -d, -f3)
    sver=$(echo "$rec" | cut -d, -f4)
    delta_b64=$(echo "$rec" | cut -d, -f5)
    sigma_b64=$(echo "$rec" | cut -d, -f6)

    total_delta=$(( total_delta + ${delta:-0} ))
    total_dver=$(( total_dver + ${dver:-0} ))
    total_sigma=$(( total_sigma + ${sigma:-0} ))
    total_sver=$(( total_sver + ${sver:-0} ))
    last_delta_b64=$delta_b64; last_sigma_b64=$sigma_b64
  done
  avg_delta=$(( total_delta / RUNS ))
  avg_dver=$(( total_dver / RUNS ))
  avg_sigma=$(( total_sigma / RUNS ))
  avg_sver=$(( total_sver / RUNS ))
  echo "$RUNS,$avg_delta,$avg_dver,$avg_sigma,$avg_sver,${last_delta_b64:-0},${last_sigma_b64:-0}" >> "$CSV_PATH"
fi

echo "CSV written: $CSV_PATH"
echo -e "${BLUE}All steps completed successfully!${NC}"