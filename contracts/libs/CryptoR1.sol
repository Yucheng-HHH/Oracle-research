// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// secp256r1 (aka P-256) crypto helpers (pure Solidity, high gas, research use)
library CryptoR1 {
    // Curve: y^2 = x^3 + ax + b over Fp, with a = -3
    uint256 internal constant P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 internal constant A = P - 3; // -3 mod p
    uint256 internal constant Gx = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 internal constant Gy = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    // ----- modular helpers over N and P -----
    function modInverseN(uint256 k) internal pure returns (uint256) {
        return powerN(k, N - 2);
    }
    function powerN(uint256 base, uint256 exp) internal pure returns (uint256) {
        uint256 res = 1;
        base %= N;
        while (exp > 0) {
            if (exp & 1 == 1) res = mulmod(res, base, N);
            base = mulmod(base, base, N);
            exp >>= 1;
        }
        return res;
    }
    function modInverseP(uint256 k) internal pure returns (uint256) {
        return powerP(k, P - 2);
    }
    function powerP(uint256 base, uint256 exp) internal pure returns (uint256) {
        uint256 res = 1;
        base %= P;
        while (exp > 0) {
            if ((exp & 1) == 1) res = mulmod(res, base, P);
            base = mulmod(base, base, P);
            exp >>= 1;
        }
        return res;
    }
    function submod(uint256 a, uint256 b, uint256 m) internal pure returns (uint256) {
        return (a >= b) ? a - b : m - (b - a);
    }

    // ----- EC ops on P-256 -----
    function ecAdd(uint256 x1, uint256 y1, uint256 x2, uint256 y2) internal pure returns (uint256, uint256) {
        uint256 s;
        if (x1 == x2 && y1 == y2) {
            // Point doubling: s = (3*x1^2 + a) / (2*y1)
            uint256 threeX2 = mulmod(3, mulmod(x1, x1, P), P);
            uint256 num = submod(threeX2, 3, P); // since a = -3
            uint256 den = mulmod(2, y1, P);
            s = mulmod(num, modInverseP(den), P);
        } else {
            // Point addition: s = (y2 - y1) / (x2 - x1)
            uint256 num = submod(y2, y1, P);
            uint256 den = submod(x2, x1, P);
            s = mulmod(num, modInverseP(den), P);
        }
        uint256 x3 = submod(submod(mulmod(s, s, P), x1, P), x2, P);
        uint256 y3 = submod(mulmod(s, submod(x1, x3, P), P), y1, P);
        return (x3, y3);
    }

    function ecMul(uint256 k, uint256 x, uint256 y) internal pure returns (uint256, uint256) {
        uint256 rx;
        uint256 ry;
        uint256 tx = x;
        uint256 ty = y;
        k %= N;
        while (k > 0) {
            if ((k & 1) == 1) {
                if (rx == 0 && ry == 0) {
                    (rx, ry) = (tx, ty);
                } else {
                    (rx, ry) = ecAdd(rx, ry, tx, ty);
                }
            }
            (tx, ty) = ecAdd(tx, ty, tx, ty);
            k >>= 1;
        }
        return (rx, ry);
    }

    function verifyEcdsa(bytes32 digest, bytes32 r, bytes32 s, bytes32 pubKeyX, bytes32 pubKeyY) internal pure returns (bool) {
        uint256 rU = uint256(r);
        uint256 sU = uint256(s);
        if (rU == 0 || sU == 0 || rU >= N || sU >= N) return false;

        uint256 sInv = modInverseN(sU);
        uint256 u1 = mulmod(uint256(digest), sInv, N);
        uint256 u2 = mulmod(rU, sInv, N);

        (uint256 p1x, uint256 p1y) = ecMul(u1, Gx, Gy);
        (uint256 p2x, uint256 p2y) = ecMul(u2, uint256(pubKeyX), uint256(pubKeyY));

        (uint256 Rx, ) = ecAdd(p1x, p1y, p2x, p2y);
        return Rx % N == rU;
    }
}


