// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./libs/Crypto.sol";

contract UniversalOracleVerifier {

    // Define a struct to hold signature data, preventing "stack too deep" errors.
    struct SignatureData {
        string data;
        bytes signature;
        bytes publicKey;
    }

    function verifyEcdsa(bytes32 digest, bytes memory signature, bytes memory publicKey) 
        internal pure returns (bool) 
    {
        if (publicKey.length != 64 || signature.length != 64) return false;
        
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
        }
        
        bytes32 pubKeyX;
        bytes32 pubKeyY;
        assembly {
            pubKeyX := mload(add(publicKey, 0x20))
            pubKeyY := mload(add(publicKey, 0x40))
        }

        return Crypto.verifyEcdsa(digest, r, s, pubKeyX, pubKeyY);
    }

    function verifySchnorr(bytes32 digest, bytes memory signature, bytes memory publicKey) 
        internal pure returns (bool) 
    {
        return verifyEcdsa(digest, signature, publicKey);
    }

    // --- Unified Verification Function ---
    // THIS IS A KEY CHANGE: Changed from 'pure' to 'view'
    function verify(
        string memory scheme,
        bytes32 digest,
        bytes memory signature,
        bytes memory publicKey
    ) public view returns (bool) {
        bytes32 schemeHash = keccak256(bytes(scheme));
        if (schemeHash == keccak256(bytes("ecdsa-k1"))) {
            return verifyEcdsa(digest, signature, publicKey);
        }
        if (schemeHash == keccak256(bytes("ecdsa-r1"))) {
            return verifyEcdsa(digest, signature, publicKey);
        }
        if (schemeHash == keccak256(bytes("ed25519"))) {
            // This now correctly calls a 'view' function from the Crypto library
            return Crypto.verifyEd25519(digest, signature, publicKey);
        }
        if (schemeHash == keccak256(bytes("schnorr-k1"))) {
            return verifySchnorr(digest, signature, publicKey);
        }
        return false;
    }

    // --- Two-Signature Verification ---
    // THIS IS A KEY CHANGE: Changed from 'pure' to 'view'
    function verifyTwoSignatures(
        string memory scheme,
        SignatureData calldata sigDataA,
        SignatureData calldata sigDataB
    ) public view returns (bool) {
        bytes32 digestA = sha256(bytes(sigDataA.data));
        bytes32 digestB = sha256(bytes(sigDataB.data));

        bool okA = verify(scheme, digestA, sigDataA.signature, sigDataA.publicKey);
        bool okB = verify(scheme, digestB, sigDataB.signature, sigDataB.publicKey);

        return okA && okB;
    }
}