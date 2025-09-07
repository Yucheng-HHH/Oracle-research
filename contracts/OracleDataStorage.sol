// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title OracleDataStorage
 * @dev Contract for measuring data read/write costs in oracle scenarios
 * @notice This contract is designed for performance analysis purposes
 */
contract OracleDataStorage {
    // Owner of the contract
    address public owner;
    
    // Data storage structures for different scenarios
    mapping(bytes32 => bytes) public dataByKey;
    mapping(bytes32 => uint256) public timestampByKey;
    mapping(bytes32 => address) public updaterByKey;
    
    // Arrays for bulk operations testing
    bytes32[] public storedKeys;
    
    // Events for tracking operations
    event DataWritten(bytes32 indexed key, uint256 dataSize, uint256 gasUsed, address updater);
    event DataRead(bytes32 indexed key, uint256 dataSize, uint256 gasUsed, address reader);
    event BulkDataWritten(uint256 itemCount, uint256 totalSize, uint256 gasUsed);
    event BulkDataRead(uint256 itemCount, uint256 totalSize, uint256 gasUsed);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Write single data item with gas measurement
     * @param key Unique identifier for the data
     * @param data The data to store
     */
    function writeData(bytes32 key, bytes calldata data) external returns (uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        
        dataByKey[key] = data;
        timestampByKey[key] = block.timestamp;
        updaterByKey[key] = msg.sender;
        
        // Add to keys array if new
        if (timestampByKey[key] == block.timestamp) {
            storedKeys.push(key);
        }
        
        gasUsed = gasBefore - gasleft();
        
        emit DataWritten(key, data.length, gasUsed, msg.sender);
        return gasUsed;
    }
    
    /**
     * @dev Read single data item with gas measurement
     * @param key Unique identifier for the data
     */
    function readData(bytes32 key) external returns (bytes memory data, uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        
        data = dataByKey[key];
        
        gasUsed = gasBefore - gasleft();
        
        emit DataRead(key, data.length, gasUsed, msg.sender);
        return (data, gasUsed);
    }
    
    /**
     * @dev Write multiple data items in batch
     * @param keys Array of unique identifiers
     * @param dataItems Array of data to store
     */
    function writeBulkData(bytes32[] calldata keys, bytes[] calldata dataItems) external returns (uint256 gasUsed) {
        require(keys.length == dataItems.length, "Arrays length mismatch");
        
        uint256 gasBefore = gasleft();
        uint256 totalSize = 0;
        
        for (uint256 i = 0; i < keys.length; i++) {
            dataByKey[keys[i]] = dataItems[i];
            timestampByKey[keys[i]] = block.timestamp;
            updaterByKey[keys[i]] = msg.sender;
            totalSize += dataItems[i].length;
            
            // Add to keys array if new
            if (timestampByKey[keys[i]] == block.timestamp) {
                storedKeys.push(keys[i]);
            }
        }
        
        gasUsed = gasBefore - gasleft();
        
        emit BulkDataWritten(keys.length, totalSize, gasUsed);
        return gasUsed;
    }
    
    /**
     * @dev Read multiple data items in batch
     * @param keys Array of unique identifiers
     */
    function readBulkData(bytes32[] calldata keys) external returns (bytes[] memory dataItems, uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        
        dataItems = new bytes[](keys.length);
        uint256 totalSize = 0;
        
        for (uint256 i = 0; i < keys.length; i++) {
            dataItems[i] = dataByKey[keys[i]];
            totalSize += dataItems[i].length;
        }
        
        gasUsed = gasBefore - gasleft();
        
        emit BulkDataRead(keys.length, totalSize, gasUsed);
        return (dataItems, gasUsed);
    }
    
    /**
     * @dev Get data info without gas measurement (view function)
     * @param key Unique identifier for the data
     */
    function getDataInfo(bytes32 key) external view returns (
        bytes memory data,
        uint256 timestamp,
        address updater,
        uint256 dataSize
    ) {
        data = dataByKey[key];
        timestamp = timestampByKey[key];
        updater = updaterByKey[key];
        dataSize = data.length;
    }
    
    /**
     * @dev Get total number of stored keys
     */
    function getStoredKeysCount() external view returns (uint256) {
        return storedKeys.length;
    }
    
    /**
     * @dev Get stored key by index
     */
    function getStoredKey(uint256 index) external view returns (bytes32) {
        require(index < storedKeys.length, "Index out of bounds");
        return storedKeys[index];
    }
    
    /**
     * @dev Clear all stored data (owner only)
     */
    function clearAllData() external onlyOwner {
        for (uint256 i = 0; i < storedKeys.length; i++) {
            delete dataByKey[storedKeys[i]];
            delete timestampByKey[storedKeys[i]];
            delete updaterByKey[storedKeys[i]];
        }
        delete storedKeys;
    }
}
