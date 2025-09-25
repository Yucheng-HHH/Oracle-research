#!/bin/bash
# This script automates the entire process of compiling, packaging, and running
# a multi-file Java application inside an Occlum SGX enclave.
set -e

# --- Configuration ---
BLUE='\033[1;34m'
NC='\033[0m'
PROJECT_DIR="pagerank_project"
JAR_NAME="pagerank.jar"

# 支持的签名方案列表，默认全部运行
# 可通过 SCHEMES 环境变量覆盖，如 SCHEMES="ecdsa-k1,ed25519"
DEFAULT_SCHEMES="ecdsa-k1,ecdsa-r1,ed25519,schnorr-k1,bls12-381"
SCHEMES=${SCHEMES:-$DEFAULT_SCHEMES}
IFS=',' read -ra SCHEME_ARRAY <<< "$SCHEMES"

# --- Set Environment Variables for Occlum Toolchain ---
# This points to the specific library paths required by Occlum's toolchain.
export JAVA_HOME=/opt/occlum/toolchains/jvm/java-11-alibaba-dragonwell
export PATH=$JAVA_HOME/bin:$PATH
export LD_LIBRARY_PATH=/opt/occlum/toolchains/gcc/x86_64-linux-musl/lib

echo -e "${BLUE}Step 1: Compiling Java source and creating executable JAR file...${NC}"
# --- Clean and Compile ---
rm -rf ${PROJECT_DIR}/classes && mkdir -p ${PROJECT_DIR}/classes
occlum-javac -cp ./${PROJECT_DIR}/lib/bcprov-jdk18on-1.79.jar -d ./${PROJECT_DIR}/classes ./${PROJECT_DIR}/src/com/mypagerank/*.java


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
  local scheme="$1"
  local out
  
  # 将签名方案和数据文件路径传给 Java 程序
  # 使用固定的数据文件路径，该路径已在 pagerank.yaml 中配置
    out=$(occlum run /usr/lib/jvm/java-11-alibaba-dragonwell/jre/bin/java -Xmx512m -XX:MaxMetaspaceSize=64m \
       -cp "/app/bcprov-jdk18on-1.79.jar:/app/${JAR_NAME}" \
       -Djava.security.properties=/dev/null \
       -Djava.security.policy=/dev/null \
       com.mypagerank.PageRank "$scheme" "/app/data/edges.csv")
  echo "$out"

  # 保存工件到按方案命名的 JSONL 文件
  save_artifacts() {
    local text="$1"
    local scheme="$2"
    local rs=$(echo "$text" | sed -n 's/^PageRank Result String:[[:space:]]*\(.*\)$/\1/p' | head -n1)
    local delta_payload=$(echo "$text" | sed -n 's/^Delta Payload:[[:space:]]*\(.*\)$/\1/p' | head -n1)
    local delta_sig=$(echo "$text" | sed -n 's/^Delta Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1)
    local sigma_sig=$(echo "$text" | sed -n 's/^Sigma Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1)
    local sig_scheme=$(echo "$text" | sed -n 's/^Sig_Scheme:[[:space:]]*\(.*\)$/\1/p' | head -n1)

    # 按方案命名 JSONL 文件
    local JSONL="../experiment_data_${scheme}.jsonl"
    if [ -n "$rs" ] && [ -n "$delta_payload" ] && [ -n "$delta_sig" ] && [ -n "$sigma_sig" ]; then
      printf '{"scheme":"%s","data":"%s","deltaPayload":"%s","deltaBase64Sig":"%s","sigmaBase64Sig":"%s"}\n' \
        "${sig_scheme:-$scheme}" "$rs" "$delta_payload" "$delta_sig" "$sigma_sig" >> "$JSONL"
      echo "Artifacts appended to $JSONL"
    else
      echo "WARN: Missing one of required fields (data/delta/sigma); skipping JSONL append for $scheme" >&2
    fi
  }

  if [ "${SAVE_ARTIFACTS:-1}" -eq 1 ]; then
    save_artifacts "$out" "$scheme"
  fi

  # Extract metrics
  local pr=$(echo "$out" | grep -oE "PR_compute_ms:[0-9]+" | cut -d: -f2)
  local tee_s=$(echo "$out" | grep -oE "Sign_ms:[0-9]+" | cut -d: -f2)
  local ts_s=$(echo "$out" | grep -oE "TS_Sign_ms:[0-9]+" | cut -d: -f2)
  local ts_v=$(echo "$out" | grep -oE "TS_Verify_ms:[0-9]+" | cut -d: -f2)
  # Robust extraction (tolerate spaces): use sed anchored at line start
  # New metrics for chained scheme (base64 sizes only as required) - all times now in microseconds
  local pr_us=$(echo "$out" | sed -n 's/^PR_compute_us:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local delta_us=$(echo "$out" | sed -n 's/^Delta_Sign_us:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local dver_us=$(echo "$out" | sed -n 's/^Delta_Verify_us:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local sigma_us=$(echo "$out" | sed -n 's/^Sigma_Sign_us:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local sver_us=$(echo "$out" | sed -n 's/^Sigma_Verify_us:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local delta_b64=$(echo "$out" | sed -n 's/^Delta_Sig_base64_bytes:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  local sigma_b64=$(echo "$out" | sed -n 's/^Sigma_Sig_base64_bytes:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | head -n1)
  # robust fallback: compute from inline base64 lines
  if [ -z "$delta_b64" ]; then delta_b64=$(echo "$out" | sed -n 's/^Delta Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1 | wc -c); fi
  if [ -z "$sigma_b64" ]; then sigma_b64=$(echo "$out" | sed -n 's/^Sigma Signature (Base64):[[:space:]]*\(.*\)$/\1/p' | head -n1 | wc -c); fi

  # Emit one CSV record values (without count) - all times now in microseconds
  echo "$pr_us,$delta_us,$dver_us,$sigma_us,$sver_us,$delta_b64,$sigma_b64"
}

# 循环每个签名方案
for SCHEME in "${SCHEME_ARRAY[@]}"; do
  echo -e "${BLUE}Running with signature scheme: $SCHEME${NC}"
  
  # 为每个方案准备独立的 CSV 文件（统一使用微秒单位）
  CSV_PATH="../tee_benchmark_${SCHEME}.csv"
  if [ ! -f "$CSV_PATH" ]; then
    echo "count,PR_compute_us,Delta_Sign_us,Delta_Verify_us,Sigma_Sign_us,Sigma_Verify_us,Delta_Sig_base64_bytes,Sigma_Sig_base64_bytes" > "$CSV_PATH"
  fi

  # Support RUNS (single value) or RUNS_LIST (comma list like 5,10,15,20,25)
  if [ -n "$RUNS_LIST" ]; then
    IFS=',' read -ra RUN_LIST_ARR <<< "$RUNS_LIST"
    for RUNS in "${RUN_LIST_ARR[@]}"; do
      total_prus=0; total_delta=0; total_dver=0; total_sigma=0; total_sver=0; last_delta_b64=0; last_sigma_b64=0

      for i in $(seq 1 "$RUNS"); do
        rec=$(run_once "$SCHEME" | tail -n1)
        prus=$(echo "$rec" | cut -d, -f1)
        delta_us=$(echo "$rec" | cut -d, -f2)
        dver_us=$(echo "$rec" | cut -d, -f3)
        sigma_us=$(echo "$rec" | cut -d, -f4)
        sver_us=$(echo "$rec" | cut -d, -f5)
        delta_b64=$(echo "$rec" | cut -d, -f6)
        sigma_b64=$(echo "$rec" | cut -d, -f7)

        total_prus=$(( total_prus + ${prus:-0} ))
        total_delta=$(( total_delta + ${delta_us:-0} ))
        total_dver=$(( total_dver + ${dver_us:-0} ))
        total_sigma=$(( total_sigma + ${sigma_us:-0} ))
        total_sver=$(( total_sver + ${sver_us:-0} ))
        last_delta_b64=$delta_b64; last_sigma_b64=$sigma_b64
      done

      avg_prus=$(( total_prus / RUNS ))
      avg_delta_us=$(( total_delta / RUNS ))
      avg_dver_us=$(( total_dver / RUNS ))
      avg_sigma_us=$(( total_sigma / RUNS ))
      avg_sver_us=$(( total_sver / RUNS ))
      echo "$RUNS,$avg_prus,$avg_delta_us,$avg_dver_us,$avg_sigma_us,$avg_sver_us,${last_delta_b64:-0},${last_sigma_b64:-0}" >> "$CSV_PATH"
    done
  else
    # Single RUN (or default 1)
    RUNS=${RUNS:-1}
    total_prus=0; total_delta=0; total_dver=0; total_sigma=0; total_sver=0; last_delta_b64=0; last_sigma_b64=0
    for i in $(seq 1 "$RUNS"); do
      rec=$(run_once "$SCHEME" | tail -n1)
      prus=$(echo "$rec" | cut -d, -f1)
      delta_us=$(echo "$rec" | cut -d, -f2)
      dver_us=$(echo "$rec" | cut -d, -f3)
      sigma_us=$(echo "$rec" | cut -d, -f4)
      sver_us=$(echo "$rec" | cut -d, -f5)
      delta_b64=$(echo "$rec" | cut -d, -f6)
      sigma_b64=$(echo "$rec" | cut -d, -f7)

      total_prus=$(( total_prus + ${prus:-0} ))
      total_delta=$(( total_delta + ${delta_us:-0} ))
      total_dver=$(( total_dver + ${dver_us:-0} ))
      total_sigma=$(( total_sigma + ${sigma_us:-0} ))
      total_sver=$(( total_sver + ${sver_us:-0} ))
      last_delta_b64=$delta_b64; last_sigma_b64=$sigma_b64
    done
    avg_prus=$(( total_prus / RUNS ))
    avg_delta_us=$(( total_delta / RUNS ))
    avg_dver_us=$(( total_dver / RUNS ))
    avg_sigma_us=$(( total_sigma / RUNS ))
    avg_sver_us=$(( total_sver / RUNS ))
    echo "$RUNS,$avg_prus,$avg_delta_us,$avg_dver_us,$avg_sigma_us,$avg_sver_us,${last_delta_b64:-0},${last_sigma_b64:-0}" >> "$CSV_PATH"
  fi

  echo "CSV written for $SCHEME: $CSV_PATH"
done

echo -e "${BLUE}All steps completed successfully!${NC}"
