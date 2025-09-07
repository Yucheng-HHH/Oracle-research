// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Crypto
 * @notice Provides pure Solidity implementations for signature verification.
 * @dev Contains self-contained logic for secp256k1 (ECDSA) and a wrapper for the Ed25519 precompile.
 */
library Crypto {
    // --- secp256k1 (ecdsa-k1, ecdsa-r1) Pure Solidity Verification ---

    uint256 internal constant P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 internal constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 internal constant Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 internal constant Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;

    function modInverse(uint256 k) internal pure returns (uint256) {
        return power(k, N - 2);
    }

    function power(uint256 base, uint256 exp) internal pure returns (uint256) {
        uint256 res = 1;
        base %= N;
        while (exp > 0) {
            if (exp % 2 == 1) res = mulmod(res, base, N);
            base = mulmod(base, base, N);
            exp /= 2;
        }
        return res;
    }

    function ecAdd(uint256 x1, uint256 y1, uint256 x2, uint256 y2) internal pure returns (uint256, uint256) {
        uint256 s;
        if (x1 == x2 && y1 == y2) { // Point doubling
            s = mulmod(3, mulmod(x1, x1, P), P); // 3 * x1^2
            s = mulmod(s, modInverseP(mulmod(2, y1, P)), P); // s = (3 * x1^2) / (2 * y1)
        } else { // Point addition
            s = submod(y2, y1, P); // y2 - y1
            s = mulmod(s, modInverseP(submod(x2, x1, P)), P); // s = (y2 - y1) / (x2 - x1)
        }
        uint256 x3 = submod(submod(mulmod(s, s, P), x1, P), x2, P); // x3 = s^2 - x1 - x2
        uint256 y3 = submod(mulmod(s, submod(x1, x3, P), P), y1, P); // y3 = s(x1 - x3) - y1
        return (x3, y3);
    }
    
    function ecMul(uint256 k, uint256 x, uint256 y) internal pure returns (uint256, uint256) {
        uint256 resX;
        uint256 resY;
        uint256 tempX = x;
        uint256 tempY = y;
        k %= N;
        while (k > 0) {
            if (k & 1 == 1) {
                if (resX == 0 && resY == 0) {
                    (resX, resY) = (tempX, tempY);
                } else {
                    (resX, resY) = ecAdd(resX, resY, tempX, tempY);
                }
            }
            (tempX, tempY) = ecAdd(tempX, tempY, tempX, tempY);
            k >>= 1;
        }
        return (resX, resY);
    }
    
    function verifyEcdsa(bytes32 digest, bytes32 r, bytes32 s, bytes32 pubKeyX, bytes32 pubKeyY) internal pure returns (bool) {
        uint256 r_uint = uint256(r);
        uint256 s_uint = uint256(s);
        if (r_uint == 0 || s_uint == 0 || r_uint >= N || s_uint >= N) return false;

        uint256 sInv = modInverse(s_uint);
        uint256 u1 = mulmod(uint256(digest), sInv, N);
        uint256 u2 = mulmod(r_uint, sInv, N);

        (uint256 p1x, uint256 p1y) = ecMul(u1, Gx, Gy);
        (uint256 p2x, uint256 p2y) = ecMul(u2, uint256(pubKeyX), uint256(pubKeyY));
        
        (uint256 R_x, ) = ecAdd(p1x, p1y, p2x, p2y);

        return R_x % N == r_uint;
    }

    // --- Ed25519 Verification ---
    // MODIFIED: Changed from 'pure' to 'view'
    function verifyEd25519(bytes32 digest, bytes memory signature, bytes memory publicKey) internal view returns (bool success) {
        if (publicKey.length != 32 || signature.length != 64) return false;
        
        bytes32 pubKey;
        bytes32 r;
        bytes32 s;
        assembly {
            pubKey  := mload(add(publicKey, 0x20))
            r       := mload(add(signature, 0x20))
            s       := mload(add(signature, 0x40))
        }

        assembly {
            let mPtr := mload(0x40)
            mstore(mPtr, digest)
            mstore(add(mPtr, 0x20), pubKey)
            mstore(add(mPtr, 0x40), r)
            mstore(add(mPtr, 0x60), s)
            // Call Ed25519 verify precompile at address 0x09
            let result := staticcall(gas(), 9, mPtr, 0x80, 0, 0)
            success := eq(result, 1)
        }
    }
    
    // --- Helper functions for modulo arithmetic over P ---
    function modInverseP(uint256 k) private pure returns (uint256) {
        return powerP(k, P - 2);
    }
    function powerP(uint256 base, uint256 exp) private pure returns (uint256) {
        uint256 res = 1;
        base %= P;
        while (exp > 0) {
            if (exp % 2 == 1) res = mulmod(res, base, P);
            base = mulmod(base, base, P);
            exp /= 2;
        }
        return res;
    }
    function submod(uint256 a, uint256 b, uint256 m) private pure returns (uint256) {
        return (a >= b) ? a - b : m - (b - a);
    }
}