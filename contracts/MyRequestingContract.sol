// contracts/FunctionsConsumer.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

contract FunctionsConsumer is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public latestRequestId;
    bytes public latestResponse;
    bytes public latestError;

    // Sepolia Testnet contract addresses and IDs
    address private constant ROUTER_ADDRESS = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 private constant DON_ID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    
    // Your subscription ID
    uint64 public subscriptionId;

    // JavaScript source code to be executed by the DON
    string private constant JAVASCRIPT_SOURCE = "const url = `https://min-api.cryptocompare.com/data/price?fsym=BTC&tsyms=USD`;"
                                             "const cryptoCompareRequest = Functions.makeHttpRequest({ url: url });"
                                             "const [response] = await Promise.all([cryptoCompareRequest]);"
                                             "const result = response.data.USD;"
                                             "return Functions.encodeUint256(Math.round(result * 100));";
    
    // Gas limit for the off-chain computation
    uint32 private constant GAS_LIMIT = 300000;

    constructor(uint64 _subscriptionId) FunctionsClient(ROUTER_ADDRESS) {
        subscriptionId = _subscriptionId;
    }

    function sendRequest() external returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(JAVASCRIPT_SOURCE);
        
        // ============== CORRECTED FUNCTION CALL ==============
        latestRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            GAS_LIMIT,
            DON_ID // Use the fixed DON ID for Sepolia
        );
        // ======================================================
        return latestRequestId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        latestResponse = response;
        latestError = err;
    }
}