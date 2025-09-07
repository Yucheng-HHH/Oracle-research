// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./libs/Crypto.sol";
import "./interfaces/IVerifier.sol";

/**
 * @title SchnorrK1Verifier
 * @dev Verifier contract for Schnorr signatures on secp256k1 curve
 * @notice Currently handles ECDSA format data until true Schnorr data is available
 */
contract SchnorrK1Verifier is IVerifier {
    /**
     * @dev Verify signature (currently ECDSA format)
     * @param digest The message digest (32 bytes)
     * @param signature The signature bytes (64 bytes: r || s)
     * @param publicKey The public key bytes (64 bytes: x || y)
     * @return True if signature is valid
     */
    function verify(bytes32 digest, bytes calldata signature, bytes calldata publicKey) external view returns (bool) {
        // Validate input lengths
        if (publicKey.length != 64 || signature.length != 64) return false;
        
        bytes32 r;
        bytes32 s;
        bytes32 pubKeyX;
        bytes32 pubKeyY;
        
        assembly {
            // Copy calldata to memory for mload access
            let sigPtr := mload(0x40) // Get free memory pointer
            calldatacopy(sigPtr, signature.offset, 64)
            r := mload(sigPtr)        // r is first 32 bytes
            s := mload(add(sigPtr, 0x20)) // s is next 32 bytes
            
            let pubKeyPtr := add(sigPtr, 0x40) // Continue in memory
            calldatacopy(pubKeyPtr, publicKey.offset, 64)
            pubKeyX := mload(pubKeyPtr)       // X is first 32 bytes
            pubKeyY := mload(add(pubKeyPtr, 0x20)) // Y is next 32 bytes
        }
        
        // Currently using ECDSA verification for compatibility with existing data format
        // TODO: Switch to actual Schnorr verification when data format is updated
        return Crypto.verifyEcdsa(digest, r, s, pubKeyX, pubKeyY);
    }
}
