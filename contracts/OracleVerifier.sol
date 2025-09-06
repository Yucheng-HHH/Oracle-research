// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract OracleVerifier {
    // ========== Keccak + EIP-191 prefixed ==========
    function verifySignature(
        string memory data,
        bytes memory signature,      // 65-byte RSV
        address expectedSigner
    ) public pure returns (bool) {
        require(signature.length == 65, "Invalid signature length");
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);

        bytes32 messageHash = keccak256(abi.encodePacked(data));
        bytes32 ethSignedMessageHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        return signer == expectedSigner;
    }

    function verifyTwoSignatures(
        string memory dataA,
        bytes memory signatureA,     // 65-byte RSV
        address expectedSignerA,
        string memory dataB,
        bytes memory signatureB,     // 65-byte RSV
        address expectedSignerB
    ) public pure returns (bool) {
        require(keccak256(bytes(dataA)) == keccak256(bytes(dataB)), "Data mismatch");
        bool okA = verifySignature(dataA, signatureA, expectedSignerA);
        bool okB = verifySignature(dataB, signatureB, expectedSignerB);
        return okA && okB;
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
    }

    // ========== SHA256 (no prefix) for TEE/TimeServer ==========
    function verifySignatureSha256(
        string memory data,
        bytes memory signature,
        address expectedSigner
    ) public pure returns (bool) {
        require(signature.length == 65, "Invalid signature length");
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);

        bytes32 digest = sha256(abi.encodePacked(data));
        address signer = ecrecover(digest, v, r, s);
        return signer == expectedSigner;
    }

    function verifyTwoSignaturesSha256(
        string memory dataA,
        bytes memory signatureA,
        address expectedSignerA,
        string memory dataB,
        bytes memory signatureB,
        address expectedSignerB
    ) public pure returns (bool) {
        bool okA = verifySignatureSha256(dataA, signatureA, expectedSignerA);
        bool okB = verifySignatureSha256(dataB, signatureB, expectedSignerB);
        return okA && okB;
    }
}