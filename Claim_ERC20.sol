// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


// FACTORY -------------------------------------------------------------------------------------


contract ClaimFactory is Ownable {

    // Array of deployed smart contracts
    address[] public claimEth;
    address[] public claimErc20;

    // Fee
    uint256 public theFee;

    // True - paused; False - not paused;
    bool public pauseCreation;

    // Events
    event CreateClaimErc20(address indexed _owner, address indexed _newSc, IERC20 _tokenAddress);
    event CreateClaimEth(address indexed _owner, address indexed _newSc);

    // Deploy a new instance of the airdrop smart contract
    function createClaimErc20(IERC20 _tokenToAidrop) external {
        require(pauseCreation == false, "Can't perform this action right now!");
        require(msg.value == theFee);

        ClaimErc20 _newAidropSc = new ClaimErc20( _tokenToAidrop, msg.sender);

        claimErc20.push(address(_newAidropSc));

        emit CreateClaimErc20(msg.sender, address(_newAidropSc), _tokenToAidrop);
    }

    // Deploy a new instance of the airdrop smart contract
    function createClaimEth() external {
        require(pauseCreation == false, "Can't perform this action right now!");
        require(msg.value == theFee);

        ClaimEther _newAidropSc = new ClaimEther(msg.sender);

        claimEth.push(address(_newAidropSc));

        emit CreateClaimEth(msg.sender, address(_newAidropSc));
    }

    // Toggle function for "isPaused" variable
    function togglePause() external onlyOwner {
        if(pauseCreation == true) {
            pauseCreation = false;
        } else {
            pauseCreation = true;
        }
    }

    function setFee(uint256 _newFee) external onlyOwner {
        theFee = _newFee;
    }

    // Withdraw ether
    function withdrawEther() external onlyOwner {
        uint256 _balance = address(this).balance;
        address _owner = owner();
        
        (bool sent, ) = _owner.call{value: _balance}("");
        require(sent, "Transaction failed!");
    }

     receive() external payable {}
}


// CLAIM ERC20 -------------------------------------------------------------------------------------


contract ClaimErc20 is Ownable, ReentrancyGuard {

    // Total ERC20 tokens to send
    uint256 public totalTokens;
    uint256 public totalClaimed;
    uint256 public usersClaimed;
    uint256 public totalUsers;

    // The IERC20 object for our ERC20 token
    IERC20 public tokenToAirdrop;

    // Link the amount to the proper address
    mapping (address => uint256) public amountByAddressERC20;

    // True - paused; False - not paused;
    bool public isPaused;

    // Events
    event ClaimTokens(address indexed _by, address indexed _to, uint256 _amount);

    // The constructor
    constructor(
        IERC20 _tokenToAirdrop,
        address _owner
        ) {
        tokenToAirdrop = _tokenToAirdrop;
        _transferOwnership(_owner);
        isPaused = false;
    }

    // Modifiers
    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller can not be another smart contract!");
        _;
    }

    // Set the amounts that needs to be claimed by each address - ERC20 tokens
    function setAddressesAndAmountsERC20(address[] calldata _to, uint256[] calldata _amounts) external onlyOwner {
        require(_to.length == _amounts.length, "Invalid lists!");

        uint256 _totalTokens = totalTokens;
        totalUsers += _to.length;

        for (uint256 i = 0; i < _to.length; i++) {
            amountByAddressERC20[_to[i]] = _amounts[i];
            _totalTokens += _amounts[i];
        }
        totalTokens = _totalTokens;
    }

    // Toggle function for "isPaused" variable
    function togglePaused() external onlyOwner {
        if(isPaused == true) {
            isPaused = false;
        } else {
            isPaused == true;
        }
    }

     // Claim ERC20 tokens
    function claimTokens(uint256 _amount, address _to) external callerIsUser nonReentrant {
        require(isPaused == false, "Can't perfrom actions while the smart contract is paused!");
        require(amountByAddressERC20[_to] != 0, "You already claimed the tokens!");
        require(_amount <= amountByAddressERC20[_to], "You are trying to claim too many tokens!");
        require(_amount <= tokenToAirdrop.balanceOf(address(this)), "Not enough tokens for this action!");
        // require(msg.sender == _to || msg.sender == addressToApprover[_to], "You don't have the right to do that!");

        amountByAddressERC20[_to] -= _amount;
        totalClaimed += _amount;
        usersClaimed++;

       require(tokenToAirdrop.transfer(_to, _amount), "Failing to transfer ERC20 tokens!");

        emit ClaimTokens(msg.sender, _to, _amount);
    }

     // Receive function to allow the smart contract to receive ether only from the owner
    receive() external payable {
        revert("Can't execute this action!");
    }

    // Withdraw tokens
    function withdrawTokens() external onlyOwner {
        uint256 _balance = tokenToAirdrop.balanceOf(address(this));
        address _owner = owner();
        
        require(tokenToAirdrop.transfer(_owner, _balance), "Failing to transfer ERC20 tokens!");
    }

    // Getters
    function returnNeededTokens() public view returns (uint256) {
        return totalTokens;
    }

    function returnScBalance() public view returns (uint256) {
        return tokenToAirdrop.balanceOf(address(this));
    }

    function returnTotalClaimed() public view returns (uint256) {
        return totalClaimed;
    }

    function returnUserClaimed() public view returns (uint256) {
        return usersClaimed;
    }

    function returnTotalUsers() public view returns (uint256) {
        return totalUsers;
    }
}


// CLAIM ETHER -------------------------------------------------------------------------------------


contract ClaimEther is Ownable, ReentrancyGuard {

    uint256 public totalTokens;
    uint256 public totalClaimed;
    uint256 public usersClaimed;
    uint256 public totalUsers;

    // Link the amount to the proper address
    mapping (address => uint256) public amountByAddressETH;

    // True - paused; False - not paused;
    bool public isPaused;

    // Events
    event ClaimEth(address indexed _by, address indexed _to, uint256 _amount);

    // The constructor
    constructor(
        address _owner
        ) {
        _transferOwnership(_owner);
        isPaused = false;
    }

    // Modifiers
    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller can not be another smart contract!");
        _;
    }

    // Toggle function for "isPaused" variable
    function togglePaused() external onlyOwner {
        if(isPaused == true) {
            isPaused = false;
        } else {
            isPaused == true;
        }
    }

    // Set the amounts that needs to be claimed by each address - ETH
    function setAddressesAndAmountsETH(address[] calldata _to, uint256[] calldata _amounts) external onlyOwner {
        require(_to.length == _amounts.length, "Invalid lists!");

        uint256 _totalTokens = totalTokens;
        totalUsers += _to.length;

        for (uint256 i = 0; i < _to.length; i++) {
            amountByAddressETH[_to[i]] = _amounts[i];
            _totalTokens += _amounts[i];
        }

        totalTokens = _totalTokens;
    }

     // Claim Ether
    function claimEther(uint256 _amount, address _to) external callerIsUser nonReentrant {
        require(isPaused == false, "Can't perfrom actions while the smart contract is paused!");
        require(amountByAddressETH[_to] != 0, "You already claimed the tokens!");
        require(_amount <= amountByAddressETH[_to], "You are trying to claim too many tokens!");
        require(_amount <= address(this).balance, "Not enough tokens for this action!");

        amountByAddressETH[_to] -= _amount;
        totalClaimed += _amount;
        usersClaimed++;

        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "Transaction failed!");

        emit ClaimEth(msg.sender, _to, _amount);
    }

     // Receive function to allow the smart contract to receive ether only from the owner
    receive() external payable onlyOwner {}

    // Withdraw ether
    function withdrawEther() external onlyOwner {
        uint256 _balance = address(this).balance;
        address _owner = owner();
        
        (bool sent, ) = _owner.call{value: _balance}("");
        require(sent, "Transaction failed!");
    }

    // Getters
    function returnNeededTokens() public view returns (uint256) {
        return totalTokens;
    }

    function returnScBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function returnTotalClaimed() public view returns (uint256) {
        return totalClaimed;
    }

    function returnUserClaimed() public view returns (uint256) {
        return usersClaimed;
    }

    function returnTotalUsers() public view returns (uint256) {
        return totalUsers;
    }
}