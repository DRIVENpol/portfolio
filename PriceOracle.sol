// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

// interface ITokenPrice_Oracle {
//     function requestBtcPrice() external;
//     function getBtcPrice() external view returns (uint256);
//     function requestEthPrice() external;
//     function getEthPrice() external view returns (uint256);
//     function requestBnbPrice() external;
//     function getBnbPrice() external view returns (uint256);
// }

contract TokenPrice_Orcale {
    address public owner;
    address public caller;

    uint256 public btcPrice;
    uint256 public ethPrice;
    uint256 public bnbPrice;

    uint256 public nextBtcCall;
    uint256 public nextEthCall;
    uint256 public nextBnbCall;

    constructor(address _owner, address _caller) {
        owner = _owner;
        caller = _caller;

        nextBtcCall = block.timestamp;
        nextEthCall = block.timestamp;
        nextBnbCall = block.timestamp;
    }

    // Modifier
    modifier onlyOracle {
        require(msg.sender == owner || msg.sender == caller, "Not authorized!");
        _;
    }

    // Events
    event callBtcPrice();
    event callEthPrice();
    event callBnbPrice();

    // Call function
    function requestBtcPrice() external {
        require(block.timestamp > nextBtcCall);
        nextBtcCall = block.timestamp + 5 minutes;

        emit callBtcPrice();
    }

    function requestEthPrice() external {
        require(block.timestamp > nextEthCall);
        nextEthCall = block.timestamp + 5 minutes;

        emit callEthPrice();
    }

    function requestBnbPrice() external {
        require(block.timestamp > nextBnbCall);
        nextBnbCall = block.timestamp + 5 minutes;

        emit callBnbPrice();
    }


    // Update function - where the connection with the server is made
    function setBtcPrice(uint256 _newPrice) external onlyOracle {
        btcPrice = _newPrice;
    }

    function setEthPrice(uint256 _newPrice) external onlyOracle {
        ethPrice = _newPrice;
    }

    function setBnbPrice(uint256 _newPrice) external onlyOracle {
        ethPrice = _newPrice;
    }

    // Return prices
    function getBtcPrice() external view returns (uint256) {
        return btcPrice;
    }

    function getEthPrice() external view returns (uint256) {
        return ethPrice;
    }

    function getBnbPrice() external view returns (uint256) {
        return bnbPrice;
    }
}