// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IVerifier.sol";

contract UniversalOracleVerifier {
    struct SignatureData {
        string data;
        bytes signature;
        bytes publicKey;
    }

    address public owner;
    mapping(bytes32 => IVerifier) private schemeToVerifier;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function registerVerifier(string memory scheme, address verifier) external onlyOwner {
        require(verifier != address(0), "invalid verifier");
        schemeToVerifier[keccak256(bytes(scheme))] = IVerifier(verifier);
    }

    function unregisterVerifier(string memory scheme) external onlyOwner {
        delete schemeToVerifier[keccak256(bytes(scheme))];
    }

    function getVerifier(string memory scheme) public view returns (IVerifier verifier) {
        verifier = schemeToVerifier[keccak256(bytes(scheme))];
        require(address(verifier) != address(0), "verifier not set");
    }

    // digest is sha256(bytes(data)) computed by router for consistency
    function verify(
        string memory scheme,
        bytes32 digest,
        bytes memory signature,
        bytes memory publicKey
    ) public view returns (bool) {
        IVerifier v = getVerifier(scheme);
        return v.verify(digest, signature, publicKey);
    }

    function verifyTwoSignatures(
        string memory scheme,
        SignatureData calldata sigDataA,
        SignatureData calldata sigDataB
    ) public view returns (bool) {
        bytes32 digestA = sha256(bytes(sigDataA.data));
        bytes32 digestB = sha256(bytes(sigDataB.data));
        IVerifier v = getVerifier(scheme);
        bool okA = v.verify(digestA, sigDataA.signature, sigDataA.publicKey);
        bool okB = v.verify(digestB, sigDataB.signature, sigDataB.publicKey);
        return okA && okB;
    }
}