// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MultiSigWallet {
    
    uint256 public requiredSigners;

    address public mainAdmin;

    mapping(address => bool) public isSigner;

    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
        uint256 signedBy;
    }

    Transaction[] public transactions;

    mapping(address => mapping(uint256 => bool)) public userSignedTransaction;

    constructor(address _mainAdmin, address[] memory signers){
        _addSigner(_mainAdmin);
        for(uint256 i = 0; i < signers.length;){
            _addSigner(signers[i]);

            unchecked {
                ++i;
            }
        }
    }

    modifier onlySigner() {
        require(_isSigner(msg.sender), "Not a signer");
        _;
    }

    modifier onlyMainAdmin() {
        require(msg.sender == mainAdmin, "Not main admin");
        _;
    }

    function submitTransaction(address destination, uint256 value, bytes memory data) external onlySigner {
        userSignedTransaction[msg.sender][transactions.length] = true;

        transactions.push(Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false,
            signedBy: 1
        }));
    }

    function signTransaction(uint256 txId) external onlySigner {
        Transaction storage transaction = transactions[txId];

        require(!transaction.executed, "Already executed");
        require(!userSignedTransaction[msg.sender][txId], "You already signed!");

        userSignedTransaction[msg.sender][txId] = true;

        transaction.signedBy++;

        if(transaction.signedBy == requiredSigners){
            _executeTransaction(txId);
        }
    }

    function addSigners(address[] memory signers) external onlyMainAdmin {
        for(uint256 i = 0; i < signers.length;){
            _addSigner(signers[i]);

            unchecked {
                ++i;
            }
        }
    }

    function removeSigners(address[] memory signers) external onlyMainAdmin {
        for(uint256 i = 0; i < signers.length;){
            _removeSigners(signers[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _executeTransaction(uint256 _txId) internal {
        Transaction storage transaction = transactions[_txId];

        transaction.executed = true;
        
        (bool success, ) = transaction.destination.call{value: transaction.value}(transaction.data);
        require(success, "Transaction failed");

        _removeTransaction(_txId);
    }

    function _addSigner(address _who) internal {
        require(!isSigner[_who], "Already a signer");
        isSigner[_who] = true;
        requiredSigners++;
    }

    function _removeSigners(address _who) internal {
        require(isSigner[_who], "Not a signer");
        isSigner[_who] = false;
        requiredSigners--;
    }

    function _removeTransaction(uint256 _txId) internal {
        transactions[_txId] = transactions[transactions.length - 1];
        transactions.pop();
    }

    function _isSigner(address _who) internal view returns(bool) {
        return isSigner[_who];
    }

    function getTransactionLenght() external view returns(uint256) {
        return transactions.length;
    }

    function getTransactionDetails(uint256 _txId) external view returns(address, uint256, bytes memory, bool, uint256) {
        Transaction storage transaction = transactions[_txId];
        return (transaction.destination, transaction.value, transaction.data, transaction.executed, transaction.signedBy);
    }
}
