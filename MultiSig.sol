// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

contract MultiSig {

    uint256 public admins = 2;
    address public secondaryAdmin;
    address public mainAdmin;

    mapping(address => mapping(uint256 => uint256)) public votedInErc20Campaign;
    mapping(address => mapping(uint256 => uint256)) public votedInEthCampaign;
    mapping(address => bool) public isHacked;
    mapping(address => bool) public isAdmin;

    struct erc20Transfer {
        uint256 id;
        address tokenAddress;
        uint256 amount;
        address to;
        uint256 yVotes;
        uint256 nVotes;
        uint256 tVotes;
        bool ended;
    }

    struct ethTransfer {
        uint256 id;
        uint256 amount;
        address to;
        uint256 yVotes;
        uint256 nVotes;
        uint256 tVotes;
        bool ended;
    }

    erc20Transfer[] public erc20Transfers;
    ethTransfer[] public ethTransfers;

    // Events
    event RequestErc20Transfer(uint256 id, address tokenAddress, uint256 amount, address to, bool status);
    event RequestEthTransfer(uint256 id, uint256 amount, address to, bool status);
    event Erc20Transfer(address token, uint256 amount, address to);
    event EthTransfer(uint256 amount, address to);

    constructor(address _mainAdmin, address _secondaryAdmin) {
        mainAdmin = _mainAdmin;
        secondaryAdmin = _secondaryAdmin;

        isAdmin[_mainAdmin] = true;
        isAdmin[_secondaryAdmin] = true;

        // Push empty erc20 transfer
        erc20Transfer memory newTransfer = erc20Transfer(erc20Transfers.length, address(0), 0, address(0), 0, 0, 0, true);
        erc20Transfers.push(newTransfer);

        // Push empty eth transfer
        ethTransfer memory newEthTransfer = ethTransfer(ethTransfers.length, 0, address(0), 0, 0, 0, true);
        ethTransfers.push(newEthTransfer);
    }

    receive() external payable {}

    // Modifiers
    modifier onlyAdmins() {
        require(isAdmin[msg.sender] == true, "You are not an admin!");
        _;
    }

    // Funcitons that have this modifier can be called
    // ONLY by the owner of the smart contract or
    // by the secondary address that was declared on deployment
    modifier onlyPrincipalAdmins() {
        require(msg.sender == mainAdmin || msg.sender == secondaryAdmin, "Can't execute this action!");
        _;
    }

    modifier onlyMainAdmin() {
        require(msg.sender == mainAdmin, "Can't execute this action!");
        _;
    }

    modifier onlySecondaryAdmin() {
        require(msg.sender == secondaryAdmin, "Can't execute this action!");
        _;
    }


    function requestErc20Transfer(address _token, uint256 _amount, address _to) external onlyAdmins {
        require(admins > 1, "This smart contract can't operate with only one admin. Please add at least one more address!");
        require(IToken(_token).balanceOf(address(this)) >= _amount, "Not enough funds!");
        require(erc20Transfers[erc20Transfers.length - 1].ended == true, "Can't push a new request. The previous request is not finished!");

        erc20Transfer memory newTransfer = erc20Transfer(erc20Transfers.length, _token, _amount, _to, 0, 0, admins, false);
        erc20Transfers.push(newTransfer);

        emit RequestErc20Transfer(erc20Transfers.length, _token, _amount, _to, false);
    }

    function requestEthTransfer(uint256 _amount, address _to) external onlyAdmins {
        require(admins > 1, "This smart contract can't operate with only one admin. Please add at least one more address!");
        require(address(this).balance >= _amount, "Not enough coins!");
        require(ethTransfers[ethTransfers.length - 1].ended == true, "Can't push a new request. The previous request is not finished!");

        ethTransfer memory newTransfer = ethTransfer(ethTransfers.length, _amount, _to, 0, 0, admins, false);
        ethTransfers.push(newTransfer);

        emit RequestEthTransfer(ethTransfers.length, _amount, _to, false);
    }

    function voteErc20Request(uint256 _id, uint256 _status) external onlyAdmins {
        require(erc20Transfers[_id].ended == false, "Can't vote in an ended campaign!");
        require(votedInErc20Campaign[msg.sender][_id] == 0, "Already voted!");

        // 1 = Yes, 2 = No
        require(_status == 1 || _status == 2, "Invalid vote!");

        votedInErc20Campaign[msg.sender][_id] = _status;

        if(_status == 1) {
            erc20Transfers[_id].yVotes++; // Increase the no. of "YES" votes
            erc20Transfers[_id].tVotes++; // Increase the total votes
        } else {
            erc20Transfers[_id].nVotes++; // Increase the no. of "NO" votes
            erc20Transfers[_id].tVotes++; // Increase the total votes
        }

        if(erc20Transfers[_id].tVotes == admins) {
            if(erc20Transfers[_id].yVotes > erc20Transfers[_id].nVotes) {
                // Push the transfer
                transferErc20(IToken(erc20Transfers[_id].tokenAddress), erc20Transfers[_id].amount, erc20Transfers[_id].to);
                // Mark the request as ended
                erc20Transfers[_id].ended = true;
            } else {
                // Mark the request as ended if:
                // "Yes" votes < "No" Votes OR
                // "Yes" votes = "No" Votes
                erc20Transfers[_id].ended = true;
            }
        }
    }

     function voteEthRequest(uint256 _id, uint256 _status) external onlyAdmins {
        require(ethTransfers[_id].ended == false, "Can't vote in an ended campaign!");
        require(votedInEthCampaign[msg.sender][_id] == 0, "Already voted!");

        // 1 = Yes, 2 = No
        require(_status == 1 || _status == 2, "Invalid vote!");

        votedInEthCampaign[msg.sender][_id] = _status;

        if(_status == 1) {
            ethTransfers[_id].yVotes++; // Increase the no. of "YES" votes
            ethTransfers[_id].tVotes++; // Increase the total votes
        } else {
            ethTransfers[_id].nVotes++; // Increase the no. of "NO" votes
            ethTransfers[_id].tVotes++; // Increase the total votes
        }

        if(ethTransfers[_id].tVotes == admins) {
            if(ethTransfers[_id].yVotes > ethTransfers[_id].nVotes) {
                // Push the transfer
                transferEth( ethTransfers[_id].amount, ethTransfers[_id].to);
                // Mark the request as ended
                ethTransfers[_id].ended = true;
            } else {
                // Mark the request as ended if:
                // "Yes" votes < "No" Votes OR
                // "Yes" votes = "No" Votes
                ethTransfers[_id].ended = true;
            }
        }
    }

    // Internal functions
    function transferEth(uint256 _amount, address _to) internal {        
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "Transaction failed!");

        emit EthTransfer(_amount, _to);
    }

    function transferErc20(IToken _tokenAddress, uint256 _amount, address _to) internal {
        require(_tokenAddress.transfer(_to, _amount), "Transfer Failed!");
    
        emit Erc20Transfer(address(_tokenAddress), _amount, _to);
    }

    // Add OR Remove admins
    function addAdmin(address _newAdmin) external onlyPrincipalAdmins {
        if(isAdmin[_newAdmin] == true) {
            revert("Admin already added!");
        } else {
            isAdmin[_newAdmin] = true;
            admins++;
        }
    }

    function removeAdmin(address _removedAdmin) external onlyPrincipalAdmins {
        require(_removedAdmin != mainAdmin && _removedAdmin != secondaryAdmin, "Can't exclude this address!");
        if (admins <= 2) { revert("Can't exclude more admins!"); }

        if(isAdmin[_removedAdmin] == false) {
            revert("Non-existent admin!");
        } else {
            isAdmin[_removedAdmin] = false;
            admins--;
        }
    }

    // Change the main admins in case of hacked accounts
    function changeSecondaryAdmin(address _newSecondaryAdmin) external onlyMainAdmin {
        require(isHacked[secondaryAdmin] == true, "Cant' change the secondary address!");

        secondaryAdmin = _newSecondaryAdmin;
    }

    function changeMainAdmin(address _newMainAdmin) external onlySecondaryAdmin {
        require(isHacked[mainAdmin] == true, "Can't change the main address!");

        mainAdmin = _newMainAdmin;
    }

    // Mark address as hacked
    function markPrimaryAsHacked() external onlyMainAdmin {
        isHacked[mainAdmin] = true;
    }

    function markSecondaryAsHacked() external onlySecondaryAdmin {
        isHacked[secondaryAdmin] = true;
    }

}