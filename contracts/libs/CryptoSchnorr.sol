// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CryptoSchnorr
 * @dev Pure Solidity implementation of Schnorr signature verification on secp256k1 curve
 * @notice Schnorr signatures use the form: s = k + e*x mod n, where e = H(R||P||m)
 */
library CryptoSchnorr {
    // secp256k1 curve parameters
    uint256 constant GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 constant GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;
    uint256 constant P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /**
     * @dev Verify Schnorr signature using BIP-340 style verification
     * @param digest The 32-byte message digest
     * @param r The R point x-coordinate (32 bytes)
     * @param s The signature scalar s (32 bytes)
     * @param pubKeyX Public key X coordinate (32 bytes)
     * @param pubKeyY Public key Y coordinate (32 bytes)
     * @return True if signature is valid
     */
    function verifySchnorr(
        bytes32 digest,
        bytes32 r,
        bytes32 s,
        bytes32 pubKeyX,
        bytes32 pubKeyY
    ) internal pure returns (bool) {
        uint256 rx = uint256(r);
        uint256 sx = uint256(s);
        uint256 px = uint256(pubKeyX);
        uint256 py = uint256(pubKeyY);
        
        // Check if r and s are valid field elements
        if (rx == 0 || rx >= P) return false;
        if (sx == 0 || sx >= N) return false;
        
        // Check if public key is on curve
        if (!isOnCurve(px, py)) return false;
        
        // Compute challenge e = H(r || pubKey || digest)
        bytes32 challenge = sha256(abi.encodePacked(r, pubKeyX, digest));
        uint256 e = uint256(challenge) % N;
        
        // Compute R' = s*G - e*P
        // This is equivalent to checking if R'.x == r
        (uint256 rpx, uint256 rpy) = schnorrVerifyPoint(sx, e, px, py);
        
        // Check if R'.x matches r
        return rpx == rx;
    }
    
    /**
     * @dev Compute R' = s*G - e*P for Schnorr verification
     */
    function schnorrVerifyPoint(
        uint256 s,
        uint256 e,
        uint256 px,
        uint256 py
    ) internal pure returns (uint256, uint256) {
        // Compute s*G
        (uint256 sgx, uint256 sgy) = ecMul(GX, GY, s);
        
        // Compute e*P
        (uint256 epx, uint256 epy) = ecMul(px, py, e);
        
        // Compute s*G - e*P = s*G + (-e*P)
        // Negate e*P by flipping Y coordinate
        epy = P - epy;
        
        // Add points
        return ecAdd(sgx, sgy, epx, epy);
    }
    
    /**
     * @dev Check if point is on secp256k1 curve: y^2 = x^3 + 7
     */
    function isOnCurve(uint256 x, uint256 y) internal pure returns (bool) {
        if (x >= P || y >= P) return false;
        
        uint256 lhs = mulmod(y, y, P);
        uint256 rhs = addmod(mulmod(mulmod(x, x, P), x, P), 7, P);
        
        return lhs == rhs;
    }
    
    /**
     * @dev Elliptic curve point multiplication: k * (x, y)
     */
    function ecMul(uint256 x, uint256 y, uint256 k) internal pure returns (uint256, uint256) {
        if (k == 0) return (0, 0);
        if (k == 1) return (x, y);
        
        uint256 x1 = x;
        uint256 y1 = y;
        uint256 x2 = 0;
        uint256 y2 = 0;
        
        while (k > 0) {
            if (k & 1 == 1) {
                if (x2 == 0 && y2 == 0) {
                    x2 = x1;
                    y2 = y1;
                } else {
                    (x2, y2) = ecAdd(x2, y2, x1, y1);
                }
            }
            (x1, y1) = ecDouble(x1, y1);
            k >>= 1;
        }
        
        return (x2, y2);
    }
    
    /**
     * @dev Elliptic curve point addition
     */
    function ecAdd(uint256 x1, uint256 y1, uint256 x2, uint256 y2) internal pure returns (uint256, uint256) {
        if (x1 == 0 && y1 == 0) return (x2, y2);
        if (x2 == 0 && y2 == 0) return (x1, y1);
        if (x1 == x2) {
            if (y1 == y2) {
                return ecDouble(x1, y1);
            } else {
                return (0, 0); // Point at infinity
            }
        }
        
        uint256 dx = addmod(x2, P - x1, P);
        uint256 dy = addmod(y2, P - y1, P);
        uint256 m = mulmod(dy, modInverse(dx, P), P);
        
        uint256 x3 = addmod(mulmod(m, m, P), P - addmod(x1, x2, P), P);
        uint256 y3 = addmod(mulmod(m, addmod(x1, P - x3, P), P), P - y1, P);
        
        return (x3, y3);
    }
    
    /**
     * @dev Elliptic curve point doubling
     */
    function ecDouble(uint256 x, uint256 y) internal pure returns (uint256, uint256) {
        if (y == 0) return (0, 0);
        
        uint256 m = mulmod(3, mulmod(x, x, P), P);
        m = mulmod(m, modInverse(mulmod(2, y, P), P), P);
        
        uint256 x2 = addmod(mulmod(m, m, P), P - mulmod(2, x, P), P);
        uint256 y2 = addmod(mulmod(m, addmod(x, P - x2, P), P), P - y, P);
        
        return (x2, y2);
    }
    
    /**
     * @dev Compute modular inverse using extended Euclidean algorithm
     */
    function modInverse(uint256 a, uint256 m) internal pure returns (uint256) {
        if (a == 0) return 0;
        
        uint256 m0 = m;
        uint256 x0 = 0;
        uint256 x1 = 1;
        
        while (a > 1) {
            uint256 q = a / m;
            uint256 t = m;
            
            m = a % m;
            a = t;
            t = x0;
            
            x0 = addmod(x1, P - mulmod(q, x0, P), P);
            x1 = t;
        }
        
        if (x1 > m0) x1 = addmod(x1, P - m0, P);
        
        return x1;
    }
}
