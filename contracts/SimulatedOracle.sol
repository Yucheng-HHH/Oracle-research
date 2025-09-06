// contracts/SimulatedOracle.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SimulatedOracle {
    address[] public whitelistedNodes;
    uint256 public requiredSignatures;
    bytes public latestData;

    constructor(address[] memory _nodes, uint256 _required) {
        whitelistedNodes = _nodes;
        requiredSignatures = _required;
    }

    function fulfill(bytes calldata _data, bytes[] calldata _signatures) external {
        // A cheap pre-condition to avoid unnecessary computation
        require(_signatures.length >= requiredSignatures, "Fulfill failed: Not enough signatures provided to potentially meet the threshold.");

        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(_data)));
        
        uint256 validSignatureCount = 0;
        // A temporary memory array to track unique signers for this specific call.
        address[] memory signersInThisCall = new address[](_signatures.length);

        for (uint i = 0; i < _signatures.length; i++) {
            address signer = recoverSigner(prefixedHash, _signatures[i]);
            
            // Check 1: Is the signer whitelisted?
            if (isWhitelisted(signer)) {
                // Check 2: Has this signer already been counted in this transaction?
                bool alreadyCounted = false;
                for (uint j = 0; j < validSignatureCount; j++) {
                    if (signersInThisCall[j] == signer) {
                        alreadyCounted = true;
                        break;
                    }
                }

                if (!alreadyCounted) {
                    signersInThisCall[validSignatureCount] = signer; // Record the unique, valid signer
                    validSignatureCount++;
                }
            }
        }
        
        // Final check: After filtering for whitelisted and unique signers, do we have enough?
        require(validSignatureCount >= requiredSignatures, "Fulfill failed: Not enough unique, valid signatures from whitelisted nodes.");

        latestData = _data;
    }

    function isWhitelisted(address _signer) internal view returns (bool) {
        for (uint i = 0; i < whitelistedNodes.length; i++) {
            if (whitelistedNodes[i] == _signer) { return true; }
        }
        return false;
    }
    
    function recoverSigner(bytes32 _hash, bytes memory _signature) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_hash, v, r, s);
    }

    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");
        assembly { r := mload(add(sig, 32)) s := mload(add(sig, 64)) v := byte(0, mload(add(sig, 96))) }
    }
}