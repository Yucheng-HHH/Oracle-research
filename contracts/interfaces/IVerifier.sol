// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVerifier {
    function verify(bytes32 digest, bytes calldata signature, bytes calldata publicKey) external view returns (bool);
}
