//SPDX-License-Identifier: MIT


/// @title ERC20 Locker
/// @notice Custom made smart contract to lock ERC20 tokens
/// @author Socarde Paul


/// Solidity version
pragma solidity ^0.8.0;

/// Imports
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// ERC20 Interface
interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// The Smart Contract
contract LockerV3 is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    /// Variables for coin fees
    uint256 public lockFee;
    uint256 public extendLockFee;
    uint256 public totalFeesForRefferals;

    /// Variables for token fees
    address public token;
    uint256 public lockFeeVo;
    uint256 public extendLockFeeVo;
    uint256 public totalFeesForRefferalsVo;

    /// Pay in coins or tokens
    bool public payInTokens;

    /// Mapp locks to token address & owner address
    mapping(address => uint256[]) public tokenToLocks;
    mapping(address => uint256[]) public ownerToLocks;

    /// Keep track of bonuses
    mapping(address => uint256) public refferalRewards;
    mapping(address => uint256) public refferalRewardsVo;

    /// Check if a deposit pinged for support
    mapping(uint256 => bool) public depositPinged;

    /// Struct for lock
    struct Lock {
        uint256 amount; // Amount to lock
        uint256 expirationDate; // Expiration time in days
        address owner; // The owner of the lock
        address tokenAddress; // The token that will be locked
    }

    /// Array of locks
    Lock[] public locks;

    /// Single error to reduce gas
    error Issue();

    /// Events
    event EmergencyPing(uint256 lockId);
    event Unlock(uint256 lockId, uint256 amount);
    event ExtendLock(uint256 lockId, uint256 period);
    event NewLock(address indexed token, uint256 amount);
    event WithdrawRefferalBonus(address indexed refferal, uint256 amount);
    event WithdrawRefferalBonusVO(address indexed refferal, uint256 amount);

    /// Constructor
    constructor() {
        _disableInitializers();
    }

    /// Initialize
    function initialize() initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();

        lockFee = 1 * 10 ** 18;
        extendLockFee = 1 * 10 ** 17;
    }

    /// Authorize upgrade (UUPS specific)
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /// Allow the smart contract to receive coins
    receive() external payable {}

    /// @dev Function to create an ERC20 lock.
    /// @param tokenAddress The token that will be locked.
    /// @param amount The amount of tokens to be locked.
    /// @param lockPeriod Lock period in days.
    /// @param refferal Refferal that will receive 10% of a transaction if somebody is recommendit it.
    function createErc20Lock(
        address tokenAddress, 
        uint256 amount, 
        uint256 lockPeriod,
        address refferal
        ) external  payable {
        /// The caller can't use his own address as refferal
        if(refferal == msg.sender) revert Issue();

        /// Token address should not be zer0
        if(tokenAddress == address(0)) revert Issue();

        /// The amount to lock should not be zero
        if(amount == 0) revert Issue();

        /// The lock period should not be zero
        if(lockPeriod == 0) revert Issue();

        /// If users needs to pay in ERC20 tokens
        if(payInTokens == true) {
         /// Msg.value should be zero
         if(msg.value != 0) revert Issue();

          /// We transfer the tokens from msg.sender to the smart contract
          if(IToken(token).transferFrom(msg.sender, address(this), lockFeeVo) != true) revert Issue();
           
           /// If the caller recommend a refferal
           if(refferal != address(0)) {
                /// We mark the bonus in tokens for this refferal
                _addBonusToRefferalVo(refferal, lockFeeVo / 10);
            }
        } else if(payInTokens == false){
           /// If we take the fee in coins
           /// Msg.value should be > fee
           if(msg.value < lockFee) revert Issue();

             /// If the caller recommend a refferal
             if(refferal != address(0)) {

                /// We mark the bonus in coins for this refferal
                _addBonusToRefferal(refferal, lockFee / 10);
            }
        }

        /// Transfer the tokens that needs to be locked to this smart contract
        if(IToken(tokenAddress).transferFrom(msg.sender, address(this), amount) != true) revert Issue();

        /// We push the lock id into the array of lock ids for this token
        tokenToLocks[tokenAddress].push(locks.length);

        /// We push the lock id into the array of lock ids of this owner
        ownerToLocks[msg.sender].push(locks.length);

        /// We create the lock
        uint256 _lockPeriod = lockPeriod * 1 days;
        locks.push(Lock(amount, block.timestamp +  _lockPeriod, msg.sender, tokenAddress));

        emit NewLock(tokenAddress, amount);
    }

    /// @dev Function to extend an ERC20 lock.
    /// @param lockId Which lock do you want to extend.
    /// @param extendPeriod For how many days do you want to extend the lock.
    /// @param refferal Refferal that will receive 10% of a transaction if somebody is recommendit it.
    function extendLock(
        uint256 lockId, 
        uint256 extendPeriod,
        address refferal
        ) external payable {
        /// The caller can't use his own address as refferal
        if(refferal == msg.sender) revert Issue();

        /// The extend period should not be zero
        if(extendPeriod == 0) revert Issue();

        /// If users needs to pay in ERC20 tokens
        if(payInTokens == true) {
         /// Msg.value should be zero   
         if(msg.value != 0) revert Issue();

          /// We transfer the tokens from msg.sender to the smart contract
          if(IToken(token).transferFrom(msg.sender, address(this), extendLockFeeVo) != true) revert Issue();

           /// If the caller recommend a refferal
           if(refferal != address(0)) {
                _addBonusToRefferalVo(refferal, extendLockFeeVo / 10);
            }
        } else if(payInTokens == false){
           /// If we take the fee in coins
           /// Msg.value should be > fee
           if(msg.value < lockFee) revert Issue();

             /// If the caller recommend a refferal
             if(refferal != address(0)) {

                /// We mark the bonus in coins for this refferal
                _addBonusToRefferal(refferal, lockFee / 10);
            }
        }

        /// We access the storage for that lock
        Lock storage _theLock = locks[lockId];

        /// Revert if the msg.sender is not the owner
        if(msg.sender != _theLock.owner) revert Issue();

        /// Revert if there are no funds left in the lock
        if(_theLock.amount == 0) revert Issue();

        /// Compute the new lock period
        uint256 _extendPeriod = extendPeriod * 1 days;

        /// If the lock expired, the new extended time will be
        /// time now + extend period
        if(block.timestamp < _theLock.expirationDate) {
            _theLock.expirationDate += _extendPeriod;
        /// Otherwise, we extend the lock
        } else if(block.timestamp >= _theLock.expirationDate){
            uint256 _elapsedTime = block.timestamp - _theLock.expirationDate;
            _theLock.expirationDate += _elapsedTime + _extendPeriod;
        }

        emit ExtendLock(lockId, _theLock.expirationDate);
    }

    /// @dev Function to withdraw tokens
    /// @param lockId From which lock do we want to withdraw
    function witdhrawTokens(uint256 lockId) external {
        /// Access the lock in storage
        Lock storage _theLock = locks[lockId];

        /// Revert if the msg.sender is not the owner
        if(msg.sender != _theLock.owner) revert Issue();

        /// Revert if there are no funds left in the lock
        if(_theLock.amount == 0) revert Issue();

        /// Revert if the lock time is not elapsed
        if(block.timestamp < _theLock.expirationDate) revert Issue();

        /// Keep the amount of the lock in a local variable
        uint256 _amount = _theLock.amount;

        /// Modify the amount in the storage
        _theLock.amount = 0;

        /// Transfer the tokens to the owner
        if(IToken(_theLock.tokenAddress).transfer(_theLock.owner, _amount) != true) revert Issue();

        emit Unlock(lockId, _amount);
    }

    /// @dev Function for refferals to withdraw their bonuses in coins
    function withdrawRefferalBonus() external {
        uint256 _rewards = refferalRewards[msg.sender];
        if(_rewards == 0) revert Issue();

        refferalRewards[msg.sender] = 0;
        totalFeesForRefferals -= _rewards;

        _sendCoins(msg.sender, _rewards);

        emit WithdrawRefferalBonus(msg.sender, _rewards);
    }

    /// @dev Function for refferals to withdraw their bonuses in tokens
    function withdrawRefferalBonusVo() external {
        uint256 _rewards = refferalRewardsVo[msg.sender];
        if(_rewards == 0) revert Issue();

        refferalRewardsVo[msg.sender] = 0;
        totalFeesForRefferalsVo -= _rewards;

        if(IToken(token).transfer(msg.sender, _rewards) != true) revert Issue();

        emit WithdrawRefferalBonusVO(msg.sender, _rewards);
    }

    /// @dev Function to ask for support
    /// @param lockId On which lock we need to take a look
    function emergencyPing(uint256 lockId) external {
        Lock memory _theLock = locks[lockId];
        if(msg.sender != _theLock.owner) revert Issue();

        depositPinged[lockId] = true;
        emit EmergencyPing(lockId);
    }

    /// @dev Function to withdraw funds from a lock before the expiration date
    /// Can be called only if the owner of the smart contract already pinged
    function emergencyWithdrawFromLock(uint256 lockId, address newReceiver) external onlyOwner {
        if(depositPinged[lockId] == false) revert Issue();
        Lock storage _theLock = locks[lockId];

        uint256 _amount = _theLock.amount;
        _theLock.amount = 0;
        depositPinged[lockId] = false;

        if(IToken(_theLock.tokenAddress).transfer(newReceiver, _amount) != true) revert Issue();
    }

    /// @dev Only-owner function to withdraw the fees in coins
    function withdrawFees() external onlyOwner {
        uint256 _fees = address(this).balance - totalFeesForRefferals;
         _sendCoins(owner(), _fees);
    }

    /// @dev Only-owner function to withdraw the fees in tokens
    function withdrawVoFees() external onlyOwner {
        uint256 _fees = IToken(token).balanceOf(address(this)) - totalFeesForRefferals;
        if(IToken(token).transfer(owner(), _fees) != true) revert Issue();
    }

    /// @dev Only-owner function to change the payment option
    function changePaymentMethod(bool option) external onlyOwner {
        if(payInTokens == option) revert Issue();
        if(option == true) {
            if(token == address(0)) revert Issue();
        }
        payInTokens = option;
    }

    /// @dev Only-owner function to change all fees
    function changeFees(
        uint256 newLockFee,
        uint256 newExtendLockFee,
        uint256 newLockFeeVo,
        uint256 newExtendLockFeeVo
    ) external onlyOwner {
        lockFee = newLockFee;
        extendLockFee = newExtendLockFee;
        lockFeeVo = newLockFeeVo;
        extendLockFeeVo = newExtendLockFeeVo;
    }

    /// @dev Only-owner function to change the token used for fees & rewards
    function changeVoToken(address newVoToken) external onlyOwner {
        token = newVoToken;
    }

    /// @dev Withdraw ERC20 tokens in case of emergency
    function withdrawERC20tokens(address _token) external onlyOwner {
        uint256 _balance = IToken(_token).balanceOf(address(this));
        IToken(token).transfer(owner(), _balance);
    }

    /// @dev Withdraw coins in case of emergency
    function withdrawCoins() external onlyOwner {
        _sendCoins(owner(), address(this).balance);
    }

    /// @dev Internal function to send coins
    function _sendCoins(address to, uint256 amount) internal {
        (bool _sent, ) = to.call{value: amount}("");
        if(_sent == false) revert Issue();
    }

    /// @dev Internal function to link a refferal to his bonus in coins
    function _addBonusToRefferal(address refferal, uint256 amount) internal {
        refferalRewards[refferal] += amount;
        totalFeesForRefferals += amount;
    }

    /// @dev Internal function to link a refferal to his bonus in tokens
    function _addBonusToRefferalVo(address refferal, uint256 amount) internal {
        refferalRewardsVo[refferal] += amount;
        totalFeesForRefferalsVo += amount;
    }

    /// @dev View function to get every lock that was made for a token
    /// @return tokenToLocks[token] An array of ids
    function getTokensToLocks(address _token) public view returns(uint256[] memory) {
        return tokenToLocks[_token];
    }

    /// @dev View function to get every lock that was made by a user
    /// @return ownerToLocks[owner] An array of ids
    function getOwnerToLocks(address owner) public view returns(uint256[] memory) {
        return ownerToLocks[owner];
    }

    /// @dev View function to get the length of the locks array
    /// @return locks.length Uint256
    function getLocksLength() public view returns(uint256) {
        return locks.length;
    }

    /// @dev View function to return the bonuses of a refferal in coins
    /// @return refferalRewards[refferal] Uint256
    function getBonusesRefferal(address refferal) public view returns(uint256) {
        return refferalRewards[refferal];
    }

    /// @dev View function to return the bonuses of a refferal in tokens
    /// @return refferalRewardsVo[refferal] Uint256
    function getBonusesRefferalVo(address refferal) public view returns(uint256) {
        return refferalRewardsVo[refferal];
    }

    /// @dev View function to return lock @lockId
    function getLockDetails(uint256 lockId) public view returns(Lock memory) {
        return locks[lockId];
    }

}