#!/bin/bash
# 测试脚本：专门测试 Ed25519 的微秒级时间精度

set -e

BLUE='\033[1;34m'
GREEN='\033[1;32m'
NC='\033[0m'

echo -e "${BLUE}Testing Ed25519 timing precision improvements${NC}"

# 备份现有的 CSV 文件
if [ -f "tee_benchmark_ed25519.csv" ]; then
    mv "tee_benchmark_ed25519.csv" "tee_benchmark_ed25519_old.csv"
    echo "Backed up old CSV file"
fi

cd occlum_instance 2>/dev/null || {
    echo "Error: occlum_instance directory not found. Please run the main build script first."
    exit 1
}

echo -e "${GREEN}Running single Ed25519 test...${NC}"

# 运行一次测试并捕获详细输出
output=$(occlum run /usr/lib/jvm/java-11-alibaba-dragonwell/jre/bin/java -Xmx512m -XX:MaxMetaspaceSize=64m \
    -cp "/app/bcprov-jdk18on-1.79.jar:/app/pagerank.jar" \
    -Djava.security.properties=/dev/null \
    -Djava.security.policy=/dev/null \
    com.mypagerank.PageRank "ed25519" "/app/data/edges.csv" 2>&1)

echo -e "${GREEN}Raw output:${NC}"
echo "$output"
echo ""

echo -e "${GREEN}Extracted timing metrics:${NC}"
echo "$output" | grep -E "(Delta_Sign_us|Delta_Verify_us|Sigma_Sign_us|Sigma_Verify_us):"

echo -e "${GREEN}Base64 signature sizes:${NC}"
echo "$output" | grep -E "(Delta_Sig_base64_bytes|Sigma_Sig_base64_bytes):"

cd ..

echo -e "${BLUE}Test completed!${NC}"
echo "Check if Ed25519 Sigma timing values are now non-zero with microsecond precision."
