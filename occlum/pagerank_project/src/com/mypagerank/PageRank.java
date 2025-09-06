package com.mypagerank;

import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

public class PageRank {
    public static void main(String[] args) {
        System.out.println("Starting PageRank Calculation...");

        // 1) 构图
        Graph graph = new Graph();
        graph.addEdge("PageA", "PageB");
        graph.addEdge("PageA", "PageC");
        graph.addEdge("PageB", "PageC");
        graph.addEdge("PageC", "PageA");
        graph.addEdge("PageD", "PageC");

        int numNodes = graph.getNumNodes();
        List<Node> allNodes = graph.getAllNodes();

        for (Node node : allNodes) {
            node.setPageRank(1.0 / numNodes);
        }

        // 2) 粗粒度计时：PageRank 计算
        final long prStart = System.nanoTime();
        int iterations = 100;
        double dampingFactor = 0.85;
        for (int i = 0; i < iterations; i++) {
            for (Node node : allNodes) {
                double rankSum = 0;
                for (Node incomingNode : node.getIncomingEdges()) {
                    rankSum += incomingNode.getPageRank() / incomingNode.getOutDegree();
                }
                double newRank = (1 - dampingFactor) / numNodes + dampingFactor * rankSum;
                node.setPageRank(newRank);
            }
        }
        final long prEnd = System.nanoTime();
        long prMs = (prEnd - prStart) / 1_000_000;

        // 3) 整理结果字符串（按名称排序，格式与链上用例一致）
        String resultString = allNodes.stream()
                .sorted(Comparator.comparing(Node::getName))
                .map(n -> n.getName() + ":" + String.format("%.4f", n.getPageRank()))
                .collect(Collectors.joining(";")) + ";";

        byte[] dataBytes = resultString.getBytes(StandardCharsets.UTF_8);

        // 4) 链式方案：Delta = TEE 对 result 签名；Sigma = TS 对 Delta Payload 签名
        // 若 secp256k1 不可用则回退 r1（开销近似）。
        byte[] deltaSigDer;        // TEE 自签（对 resultString）
        long deltaSignMs;          // TEE 生成 delta 签名时间

        long deltaVerifyMs;        // TS 验证 delta（TEE 的签名）耗时
        String deltaPayloadStr = ""; // TS 对其进行签名的载荷（包含 result 摘要等）

        byte[] sigmaSigDer;        // TS 对 deltaPayload 的签名
        long sigmaSignMs;          // TS 生成 sigma 时间
        long sigmaVerifyMs;        // TEE 验证 sigma 时间
        try {
            String usedCurve = "secp256k1";
            KeyPairGenerator kpg = KeyPairGenerator.getInstance("EC");
            try {
                kpg.initialize(new ECGenParameterSpec("secp256k1"));
            } catch (Exception __eCurve) {
                // fallback if k1 unsupported in this JRE
                kpg.initialize(new ECGenParameterSpec("secp256r1"));
                usedCurve = "secp256r1";
            }
            KeyPair kp = kpg.generateKeyPair();

            long s0 = System.nanoTime();
            Signature sig = Signature.getInstance("SHA256withECDSA");
            sig.initSign(kp.getPrivate());
            sig.update(dataBytes);
            deltaSigDer = sig.sign();
            long s1 = System.nanoTime();
            deltaSignMs = (s1 - s0) / 1_000_000;

            // Time Server: 使用独立密钥
            KeyPairGenerator tsKpg = KeyPairGenerator.getInstance("EC");
            try {
                tsKpg.initialize(new ECGenParameterSpec("secp256k1"));
            } catch (Exception __eCurveTs) {
                tsKpg.initialize(new ECGenParameterSpec("secp256r1"));
                usedCurve = "secp256r1";
            }
            KeyPair tsKp = tsKpg.generateKeyPair();

            // TS 验证 delta（TEE 对 result 的签名）
            long v0 = System.nanoTime();
            Signature tsVerifyDelta = Signature.getInstance("SHA256withECDSA");
            tsVerifyDelta.initVerify(kp.getPublic());
            tsVerifyDelta.update(dataBytes);
            boolean deltaOk = tsVerifyDelta.verify(deltaSigDer);
            long v1 = System.nanoTime();
            deltaVerifyMs = (v1 - v0) / 1_000_000;
            if (!deltaOk) {
                System.out.println("WARN: TS failed to verify delta signature");
            }

            // 组装 Delta Payload（绑定 result 与 delta 签名）
            String resultHashHex = bytesToHex(sha256(dataBytes));
            String deltaSigHashHex = bytesToHex(sha256(deltaSigDer));
            deltaPayloadStr = "TSv1|" + resultHashHex + "|" + deltaSigHashHex + "|" + System.currentTimeMillis();
            byte[] deltaPayloadBytes = deltaPayloadStr.getBytes(StandardCharsets.UTF_8);

            // TS 对 Delta Payload 签名，得到 Sigma
            long tsS0 = System.nanoTime();
            Signature tsSig = Signature.getInstance("SHA256withECDSA");
            tsSig.initSign(tsKp.getPrivate());
            tsSig.update(deltaPayloadBytes);
            sigmaSigDer = tsSig.sign();
            long tsS1 = System.nanoTime();
            sigmaSignMs = (tsS1 - tsS0) / 1_000_000;

            // TEE 验证 Sigma
            long sv0 = System.nanoTime();
            Signature teeVerifySigma = Signature.getInstance("SHA256withECDSA");
            teeVerifySigma.initVerify(tsKp.getPublic());
            teeVerifySigma.update(deltaPayloadBytes);
            boolean sigmaOk = teeVerifySigma.verify(sigmaSigDer);
            long sv1 = System.nanoTime();
            sigmaVerifyMs = (sv1 - sv0) / 1_000_000;
            if (!sigmaOk) {
                System.out.println("WARN: TEE failed to verify sigma signature");
            }
            System.out.println("Curve:" + usedCurve);
        } catch (Exception e) {
            // 回退：如签名不可用，则输出 0 并给出空签名
            deltaSigDer = new byte[0];
            deltaSignMs = 0L;
            deltaVerifyMs = 0L;
            sigmaSigDer = new byte[0];
            sigmaSignMs = 0L;
            sigmaVerifyMs = 0L;
            System.out.println("WARN: signature not generated due to: " + e.getMessage());
        }

        String deltaBase64Sig = Base64.getEncoder().encodeToString(deltaSigDer);
        String sigmaBase64Sig = Base64.getEncoder().encodeToString(sigmaSigDer);

        // 5) 打印可解析指标（供外部脚本提取到 CSV）
        System.out.println("PageRank Result String: " + resultString);
        System.out.println("Delta Payload: " + deltaPayloadStr);
        System.out.println("Delta Signature (Base64): " + deltaBase64Sig);
        System.out.println("Sigma Signature (Base64): " + sigmaBase64Sig);
        System.out.println("PR_compute_ms:" + prMs);
        System.out.println("Delta_Sign_ms:" + deltaSignMs);
        System.out.println("Delta_Verify_ms:" + deltaVerifyMs);
        System.out.println("Sigma_Sign_ms:" + sigmaSignMs);
        System.out.println("Sigma_Verify_ms:" + sigmaVerifyMs);
        System.out.println("Delta_Sig_base64_bytes:" + deltaBase64Sig.length());
        System.out.println("Sigma_Sig_base64_bytes:" + sigmaBase64Sig.length());

        // 6) 仍保留详细结果打印（便于手动检查）
        System.out.println("Final PageRank values after " + iterations + " iterations:");
        for (Node node : allNodes) {
            System.out.printf("- %s: %.4f\n", node.getName(), node.getPageRank());
        }
    }

    private static byte[] sha256(byte[] data) {
        try {
            return java.security.MessageDigest.getInstance("SHA-256").digest(data);
        } catch (Exception e) {
            return new byte[32];
        }
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}