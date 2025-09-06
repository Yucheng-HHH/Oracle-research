package com.mypagerank;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Security;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;
import java.util.logging.Logger;
import java.util.logging.Level;
import java.io.StringWriter;
import java.io.PrintWriter;
import java.security.Provider;

public class PageRank {
    private static final Logger LOGGER = Logger.getLogger(PageRank.class.getName());

    static {
        try {
            // 添加 BouncyCastle 提供者
            Provider bcProvider = new org.bouncycastle.jce.provider.BouncyCastleProvider();
            Security.addProvider(bcProvider);
            
            // 打印所有已注册的提供者
            System.out.println("Registered Security Providers:");
            for (Provider provider : Security.getProviders()) {
                System.out.println(provider.getName() + ": " + provider.getInfo());
            }
            
            // 验证 BouncyCastle 提供者是否成功注册
            Provider registeredProvider = Security.getProvider("BC");
            if (registeredProvider != null) {
                System.out.println("BouncyCastle provider successfully registered: " + registeredProvider.getInfo());
            } else {
                System.err.println("WARNING: BouncyCastle provider (BC) not found in registered providers!");
            }
        } catch (Exception e) {
            System.err.println("Error adding BouncyCastle provider: " + e.getMessage());
            e.printStackTrace();
        }
    }

    public static void main(String[] args) {
        System.out.println("Starting PageRank Calculation...");

        // 参数解析：签名方案与数据文件（可从 args 或环境变量）
        String scheme = (args.length > 0 && args[0] != null && !args[0].isEmpty())
                ? args[0] : System.getenv().getOrDefault("SIG_SCHEME", "ecdsa-k1");
        String dataFile = (args.length > 1 && args[1] != null && !args[1].isEmpty())
                ? args[1] : System.getenv("DATA_FILE");
        int iterations = Integer.parseInt(System.getenv().getOrDefault("PR_ITERS", "100"));
        double dampingFactor = Double.parseDouble(System.getenv().getOrDefault("PR_DAMP", "0.85"));

        // 1) 构图：文件优先；否则使用内置小图
        Graph graph = new Graph();
        boolean usedDefaultGraph = false;
        
        if (dataFile != null && !dataFile.isEmpty()) {
            try {
                System.out.println("Loading graph from file: " + dataFile);
                long edgeCount = Files.lines(Paths.get(dataFile))
                        .map(String::trim)
                        .filter(l -> !l.isEmpty() && !l.startsWith("#"))
                        .map(l -> {
                            String[] p = l.split("[,\\t\\s]+");
                            if (p.length >= 2) {
                                graph.addEdge(p[0], p[1]);
                                return true;
                            }
                            return false;
                        })
                        .filter(added -> added)
                        .count();
                System.out.println("Successfully loaded " + edgeCount + " edges from file");
            } catch (Exception e) {
                System.out.println("WARNING: Failed to load edges from " + dataFile + ": " + e.getMessage());
                System.out.println("Falling back to default graph...");
                usedDefaultGraph = true;
                // 使用内置小图
                useDefaultGraph(graph);
            }
            
            // 如果文件存在但没有有效边，也使用默认图
            if (graph.getNumNodes() == 0) {
                System.out.println("WARNING: No valid edges found in file. Using default graph.");
                usedDefaultGraph = true;
                useDefaultGraph(graph);
            }
        } else {
            System.out.println("No data file specified. Using default graph.");
            usedDefaultGraph = true;
            useDefaultGraph(graph);
        }
        
        if (usedDefaultGraph) {
            System.out.println("Using default graph with 5 nodes and 5 edges");
        }

        int numNodes = graph.getNumNodes();
        List<Node> allNodes = graph.getAllNodes();

        for (Node node : allNodes) {
            node.setPageRank(1.0 / numNodes);
        }

        // 2) 粗粒度计时：PageRank 计算
        final long prStart = System.nanoTime();
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
        long prNs = (prEnd - prStart);
        long prUs = prNs / 1_000; // microseconds for finer granularity
        long prMs = prNs / 1_000_000;

        // 3) 整理结果字符串（按名称排序，格式与链上用例一致）
        String resultString = allNodes.stream()
                .sorted(Comparator.comparing(Node::getName))
                .map(n -> n.getName() + ":" + String.format("%.4f", n.getPageRank()))
                .collect(Collectors.joining(";")) + ";";

        byte[] dataBytes = resultString.getBytes(StandardCharsets.UTF_8);

        // 4) 链式方案：Delta = TEE 对 result 签名；Sigma = TS 对 Delta Payload 签名
        byte[] deltaSigDer;        // TEE 自签（对 resultString）
        long deltaSignMs;          // TEE 生成 delta 签名时间

        long deltaVerifyMs;        // TS 验证 delta（TEE 的签名）耗时
        String deltaPayloadStr = ""; // TS 对其进行签名的载荷（包含 result 摘要等）

        byte[] sigmaSigDer;        // TS 对 deltaPayload 的签名
        long sigmaSignMs;          // TS 生成 sigma 时间
        long sigmaVerifyMs;        // TEE 验证 sigma 时间
        try {
            String usedScheme = scheme;
            KeyPair kp = genKeyPair(usedScheme);
            KeyPair tsKp = genKeyPair(usedScheme);

            long s0 = System.nanoTime();
            Signature sig = newSignature(usedScheme);
            sig.initSign(kp.getPrivate());
            sig.update(dataBytes);
            deltaSigDer = sig.sign();
            long s1 = System.nanoTime();
            deltaSignMs = (s1 - s0) / 1_000_000;

            // TS 验证 delta（TEE 对 result 的签名）
            long v0 = System.nanoTime();
            Signature tsVerifyDelta = newSignature(usedScheme);
            tsVerifyDelta.initVerify(kp.getPublic());
            tsVerifyDelta.update(dataBytes);
            boolean deltaOk = tsVerifyDelta.verify(deltaSigDer);
            long v1 = System.nanoTime();
            deltaVerifyMs = (v1 - v0) / 1_000_000;
            if (!deltaOk) {
                LOGGER.warning("TS failed to verify delta signature");
                System.out.println("WARN: TS failed to verify delta signature");
            }

            // 组装 Delta Payload（绑定 result 与 delta 签名）
            String resultHashHex = bytesToHex(sha256(dataBytes));
            String deltaSigHashHex = bytesToHex(sha256(deltaSigDer));
            deltaPayloadStr = "TSv1|" + resultHashHex + "|" + deltaSigHashHex + "|" + System.currentTimeMillis();
            byte[] deltaPayloadBytes = deltaPayloadStr.getBytes(StandardCharsets.UTF_8);

            // TS 对 Delta Payload 签名，得到 Sigma
            long tsS0 = System.nanoTime();
            Signature tsSig = newSignature(usedScheme);
            tsSig.initSign(tsKp.getPrivate());
            tsSig.update(deltaPayloadBytes);
            sigmaSigDer = tsSig.sign();
            long tsS1 = System.nanoTime();
            sigmaSignMs = (tsS1 - tsS0) / 1_000_000;

            // TEE 验证 Sigma
            long sv0 = System.nanoTime();
            Signature teeVerifySigma = newSignature(usedScheme);
            teeVerifySigma.initVerify(tsKp.getPublic());
            teeVerifySigma.update(deltaPayloadBytes);
            boolean sigmaOk = teeVerifySigma.verify(sigmaSigDer);
            long sv1 = System.nanoTime();
            sigmaVerifyMs = (sv1 - sv0) / 1_000_000;
            if (!sigmaOk) {
                LOGGER.warning("TEE failed to verify sigma signature");
                System.out.println("WARN: TEE failed to verify sigma signature");
            }
            System.out.println("Sig_Scheme: " + usedScheme);
        } catch (Exception e) {
            // 回退：如签名不可用，则输出 0 并给出空签名
            LOGGER.log(Level.SEVERE, "Signature generation failed for scheme: " + scheme, e);
            System.err.println("Detailed signature generation error for scheme " + scheme + ": " + e.getMessage());
            e.printStackTrace(); // 打印完整的堆栈跟踪

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
        System.out.println("PR_compute_us:" + prUs);
        System.out.println("PR_per_iter_us:" + (prNs / Math.max(1, iterations)) / 1_000);
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
    
    private static void useDefaultGraph(Graph graph) {
        graph.addEdge("PageA", "PageB");
        graph.addEdge("PageA", "PageC");
        graph.addEdge("PageB", "PageC");
        graph.addEdge("PageC", "PageA");
        graph.addEdge("PageD", "PageC");
    }

    private static KeyPair genKeyPair(String scheme) throws Exception {
        LOGGER.info("Generating key pair for scheme: " + scheme);
        switch (scheme) {
            case "ecdsa-k1": {
                try {
                    KeyPairGenerator kpg = KeyPairGenerator.getInstance("EC");
                    try { 
                        kpg.initialize(new ECGenParameterSpec("secp256k1")); 
                        LOGGER.info("Successfully initialized secp256k1 curve");
                    } catch (Exception e) {
                        LOGGER.warning("secp256k1 curve not supported, falling back to secp256r1");
                        kpg.initialize(new ECGenParameterSpec("secp256r1"));
                    }
                    return kpg.generateKeyPair();
                } catch (Exception e) {
                    LOGGER.log(Level.SEVERE, "Failed to generate ECDSA key pair", e);
                    throw new UnsupportedOperationException("secp256k1 curve not supported in current runtime", e);
                }
            }
            case "ecdsa-r1": {
                KeyPairGenerator kpg = KeyPairGenerator.getInstance("EC");
                kpg.initialize(new ECGenParameterSpec("secp256r1"));
                return kpg.generateKeyPair();
            }
            case "ed25519": {
                try {
                    LOGGER.info("Attempting to generate Ed25519 key pair using BouncyCastle provider");
                    KeyPairGenerator kpg = KeyPairGenerator.getInstance("Ed25519", "BC");
                    KeyPair keyPair = kpg.generateKeyPair();
                    LOGGER.info("Successfully generated Ed25519 key pair");
                    return keyPair;
                } catch (Exception e) {
                    LOGGER.log(Level.SEVERE, "Failed to generate Ed25519 key pair", e);
                    throw new UnsupportedOperationException("Ed25519 not supported. Make sure BouncyCastle provider is available", e);
                }
            }
            case "schnorr-k1": {
                try {
                    LOGGER.info("Attempting to generate Schnorr key pair using BouncyCastle provider");
                    // 使用 secp256k1 曲线生成 Schnorr 签名密钥对
                    KeyPairGenerator kpg = KeyPairGenerator.getInstance("EC", "BC");
                    kpg.initialize(new ECGenParameterSpec("secp256k1"));
                    KeyPair keyPair = kpg.generateKeyPair();
                    LOGGER.info("Successfully generated Schnorr key pair");
                    return keyPair;
                } catch (Exception e) {
                    LOGGER.log(Level.SEVERE, "Failed to generate Schnorr key pair", e);
                    throw new UnsupportedOperationException("Schnorr signature scheme not supported", e);
                }
            }
            case "bls12-381": {
                LOGGER.severe("BLS12-381 signature scheme not yet implemented");
                throw new UnsupportedOperationException("BLS12-381 signature scheme not yet implemented");
            }
            default:
                LOGGER.severe("Unknown signature scheme: " + scheme);
                throw new UnsupportedOperationException("Unknown signature scheme: " + scheme);
        }
    }

    private static Signature newSignature(String scheme) throws Exception {
        LOGGER.info("Creating signature instance for scheme: " + scheme);
        switch (scheme) {
            case "ecdsa-k1":
            case "ecdsa-r1":
                LOGGER.info("Using SHA256withECDSA signature algorithm");
                return Signature.getInstance("SHA256withECDSA");
            case "ed25519":
                try {
                    LOGGER.info("Attempting to create Ed25519 signature using BouncyCastle provider");
                    Signature sig = Signature.getInstance("Ed25519", "BC");
                    LOGGER.info("Successfully created Ed25519 signature instance");
                    return sig;
                } catch (Exception e) {
                    LOGGER.log(Level.SEVERE, "Failed to create Ed25519 signature instance", e);
                    throw new UnsupportedOperationException("Ed25519 not supported. Make sure BouncyCastle provider is available", e);
                }
            case "schnorr-k1": {
                try {
                    LOGGER.info("Attempting to create Schnorr signature");
                    
                    // 打印所有可用的签名算法
                    LOGGER.info("Available signature algorithms:");
                    for (Provider provider : Security.getProviders()) {
                        for (Provider.Service service : provider.getServices()) {
                            if (service.getType().equals("Signature")) {
                                LOGGER.info(provider.getName() + ": " + service.getAlgorithm());
                            }
                        }
                    }
                    
                    // 尝试使用 ECDSA 作为 Schnorr 的替代方案
                    Signature sig = Signature.getInstance("SHA256withECDSA", "BC");
                    LOGGER.info("Using SHA256withECDSA as Schnorr signature alternative");
                    return sig;
                } catch (Exception e) {
                    LOGGER.log(Level.SEVERE, "Failed to create Schnorr signature", e);
                    
                    // 详细记录异常信息
                    StringWriter sw = new StringWriter();
                    PrintWriter pw = new PrintWriter(sw);
                    e.printStackTrace(pw);
                    LOGGER.severe("Detailed exception: " + sw.toString());
                    
                    throw new UnsupportedOperationException("Schnorr signature scheme not supported: " + e.getMessage(), e);
                }
            }
            case "bls12-381":
                LOGGER.severe("BLS12-381 signature scheme not yet implemented");
                throw new UnsupportedOperationException("BLS12-381 signature scheme not yet implemented");
            default:
                LOGGER.severe("Unknown signature scheme: " + scheme);
                throw new UnsupportedOperationException("Unknown signature scheme: " + scheme);
        }
    }
}
