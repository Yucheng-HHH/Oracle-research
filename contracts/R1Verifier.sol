// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IVerifier.sol";
import "./libs/CryptoR1.sol";

contract R1Verifier is IVerifier {
    function verify(bytes32 digest, bytes calldata signature, bytes calldata publicKey) external view returns (bool) {
        if (publicKey.length != 64 || signature.length != 64) return false;
        bytes32 r;
        bytes32 s;
        bytes32 px;
        bytes32 py;
        assembly {
            let sigPtr := mload(0x40)
            calldatacopy(sigPtr, signature.offset, 64)
            r := mload(sigPtr)
            s := mload(add(sigPtr, 0x20))

            let pkPtr := add(sigPtr, 0x40)
            calldatacopy(pkPtr, publicKey.offset, 64)
            px := mload(pkPtr)
            py := mload(add(pkPtr, 0x20))
        }
        return CryptoR1.verifyEcdsa(digest, r, s, px, py);
    }
}


