# Oracle-research: TEE(PageRank) → On-chain Verification 一条龙指南

本文档说明如何运行链下 TEE 实验（Occlum 内运行 PageRank 并生成链式签名 delta/sigma），以及如何在链上进行两签校验与基准测试（gas 与 calldata）。

## 目录结构与关键文件

- 链下（Occlum）
  - `occlum/build_and_run_pagerank.sh`: 一键构建 Occlum 镜像并运行 Java 程序、采样并落地数据
  - `occlum/pagerank_project/src/com/mypagerank/PageRank.java`: PageRank 与签名链（delta/sigma）的粗粒度计时与输出
  - 输出数据
    - `occlum/experiment_data.jsonl`: 每条 run 的上链所需输入（JSONL）
    - `occlum/tee_benchmark_coarse.csv`: 计算/通信开销（均值）

- 链上（Hardhat）
  - 合约：`contracts/OracleVerifier.sol`
    - 支持 keccak+前缀 与 SHA-256 无前缀两套验签；本实验使用 `verifyTwoSignaturesSha256`
  - 脚本：
    - `scripts/deployOracleVerifier.ts`: 部署合约
    - `scripts/verifyOcclumResults.ts`: 读取 JSONL 最新一条，执行链上两签验证（TEE+TimeServer）
    - `scripts/benchmarkOnchain.ts`: 批量消耗 JSONL，估算两签/单签的 gas 与 calldata 大小
    - `scripts/utils/signatureUtils.ts`: Base64(DER)→(r,s) 低-s 规范化→RSV 与地址恢复、解析 JSONL

## 先决条件

- Node.js 18+，pnpm/npm 任一
- Hardhat 环境：`npm i`
- 部署与走链需配置 `.env`（如使用 Sepolia）：
  - `SEPOLIA_RPC_URL=...`
  - `PRIVATE_KEY=0x...`（测试私钥）
- Occlum 容器/环境（内置 java-11 dragonwell 与 occlum 工具链）。在容器内执行链下脚本。

## 一、链下实验（Occlum）

目的：
- 在 TEE 内运行 PageRank，生成 TEE 对 result 的签名 delta（Base64/DER），
- TS 验证 delta 后，生成对 deltaPayload 的签名 sigma（Base64/DER），
- 记录 delta/sigma 的生成/验证时延与通信开销（Base64 字节数），
- 将上链所需输入写入 `experiment_data.jsonl`。

步骤（在 Occlum 容器内）：
1) 进入项目根目录，执行
```
bash occlum/build_and_run_pagerank.sh
```
2) 批量采样（按 5,10,15,20,25 分组）
```
RUNS_LIST=5,10,15,20,25 bash occlum/build_and_run_pagerank.sh
```

输出与含义：
- `occlum/experiment_data.jsonl` 每行 JSON：
  - `data`: PageRank 结果字符串
  - `deltaPayload`: `TSv1|sha256(data)|sha256(deltaSigDER)|timestamp`
  - `deltaBase64Sig`: TEE 对 data 的签名（Base64/DER）
  - `sigmaBase64Sig`: TS 对 deltaPayload 的签名（Base64/DER）
- `occlum/tee_benchmark_coarse.csv` 列：
  - `Delta_Sign_ms, Delta_Verify_ms, Sigma_Sign_ms, Sigma_Verify_ms`
  - `Delta_Sig_base64_bytes, Sigma_Sig_base64_bytes`
  - 每行 `count` 为该组请求数，时间为均值，字节数为单次（近似恒定）

说明：Java 默认尝试 secp256k1，不可用则回退 secp256r1（仅用于链下开销测量）。

## 二、链上实验（Hardhat）

目的：对同一请求验证两份签名（TEE delta、TS sigma），并统计 gas 与 calldata 大小。

1) 安装与编译
```
npm i
npx hardhat compile
```

2) 部署合约 `OracleVerifier`
```
npx hardhat run scripts/deployOracleVerifier.ts --network sepolia
```
记录部署地址，并在 PowerShell（或 Bash）设置环境变量：
```
# PowerShell
$env:CONTRACT_ADDRESS="0xYourVerifierAddress"
```

3) 单次验证（读取 JSONL 最新一条）
```
npx hardhat run scripts/verifyOcclumResults.ts --network sepolia
```
预期：
- 打印恢复的 TEE/TS 地址
- `verifyTwoSignaturesSha256: true` 表示两签均有效

4) 基准测试（按 5/10/15/20/25 分组，顺序消费 JSONL）
```
# 双签（TEE+TS）
$env:MODE="two"
npx hardhat run scripts/benchmarkOnchain.ts --network sepolia

# 单签（对照组，基于 data+delta 的单签验签）
$env:MODE="one"
npx hardhat run scripts/benchmarkOnchain.ts --network sepolia
```
输出：
- `benchmark_two.csv` / `benchmark_one.csv`，列：`count,avg_gas,calldata_bytes`
- gas 使用 estimateGas（不落链），calldata 为 ABI 编码后字节数

## 数据与格式对齐（非常重要）

- 链下真实传输：Base64 文本（DER 编码的 ECDSA 签名）
  - 记录的通信开销应按 Base64 字节数统计（CSV 中已给出）
- 链上需要 RSV 65 字节格式
  - 脚本会自动：Base64→DER→(r,s) 低-s→推导 v→RSV
- 验签摘要：本实验使用 `sha256(data)` 无前缀（TEE 与 TS 皆如此）
  - 合约端使用 `verifySignatureSha256`/`verifyTwoSignaturesSha256`

## 常见问题

- unknown function/接口不存在：
  - 请确认合约已编译并重新部署，且 `CONTRACT_ADDRESS` 指向最新版本（包含 `verifyTwoSignaturesSha256`）。
- non-canonical s 错误：
  - 已在脚本内做低-s 规范化；若仍报错，请检查 Base64 是否被截断。
- 解析 JSON 失败：
  - 确保 `occlum/experiment_data.jsonl` 存在且每行包含 `data, deltaPayload, deltaBase64Sig, sigmaBase64Sig`。

## 快速参考命令

- 链下（容器内）
  - 单次：`bash occlum/build_and_run_pagerank.sh`
  - 批量：`RUNS_LIST=5,10,15,20,25 bash occlum/build_and_run_pagerank.sh`
- 链上
  - 编译：`npx hardhat compile`
  - 部署：`npx hardhat run scripts/deployOracleVerifier.ts --network sepolia`
  - 验证：`npx hardhat run scripts/verifyOcclumResults.ts --network sepolia`
  - 基准：`$env:MODE="two"; npx hardhat run scripts/benchmarkOnchain.ts --network sepolia`

