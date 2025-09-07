// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./libs/Crypto.sol";
import "./interfaces/IVerifier.sol";

contract K1Verifier is IVerifier {
    function verify(bytes32 digest, bytes calldata signature, bytes calldata publicKey) external view returns (bool) {
        if (publicKey.length != 64 || signature.length != 64) return false;
        bytes32 r;
        bytes32 s;
        bytes32 pubKeyX;
        bytes32 pubKeyY;
        assembly {
            let sigPtr := mload(0x40)
            calldatacopy(sigPtr, signature.offset, 64)
            r := mload(sigPtr)
            s := mload(add(sigPtr, 0x20))

            let pkPtr := add(sigPtr, 0x40)
            calldatacopy(pkPtr, publicKey.offset, 64)
            pubKeyX := mload(pkPtr)
            pubKeyY := mload(add(pkPtr, 0x20))
        }
        return Crypto.verifyEcdsa(digest, r, s, pubKeyX, pubKeyY);
    }
}
