//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Enhanced Ownership Model for Ownable.sol
 * @notice In this model, rather than directly transferring ownership to a new address, we first propose
 *         an address for ownership privileges. Subsequently, the proposed address has the option to claim 
 *         ownership. This system offers developers an added layer of control. If an unintended address is 
 *         proposed, they can promptly suggest an alternative.
 * @author Socarde Paul
*/

contract Ownable {
    /// Variables
    address public currentOwner;
    address public proposedOwner;

    /// Events
    event NewOwnerProposed(address indexed proposedOwner);
    event OwnershipClaimed(address indexed newOwner);

    /// Constructor
    constructor() {
        currentOwner = msg.sender;
    }

    /// Modifier
    modifier onlyOwner {
        require(msg.sender == currentOwner, "You are not the owner!");
        _;
    }

    /// @dev Function to propose a new owner
    /// @param _newOwner Address proposed to take the ownership
    function proposeNewOwner(address _newOwner) external onlyOwner {
        proposedOwner = _newOwner;

        emit NewOwnerProposed(_newOwner);
    }

    /// @dev Function to claim the ownership
    function claimOwnership() external {
        require(msg.sender == proposedOwner, "You are not the proposed owner!");
        currentOwner = msg.sender;
        proposedOwner = address(0);

        emit OwnershipClaimed(msg.sender);
    }

    /// @dev Function to return the owner
    /// @return _owner Address of current owner
    function getOwner() public view returns(address _owner) {
        _owner = currentOwner;
    }
}