// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IFactory {
    function emergencyPing() external;
}


contract Migrator {

    /// Variables for migration
    address public tokenA;
    address public tokenB;
    address public ownerTokenA;
    address public ownerTokenB;
    address public generalOwner;

    address public factory;

    uint256 public denominator = 1; // If we want to give less/more tokens
    uint256 public doOperations; // 0 - nothing; 1 - give more tokens; 2 - give less tokens

    /// Variables for analytics
    uint256 public tokensSent;
    uint256 public tokensReceived;

    /// Can withdraw
    bool public canWithdraw;
    bool public canDeposit;

    /// Map the old amount to the new amount
    mapping(address => uint256) public holderToNewAmount;

    /// Events
    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address indexed who, uint256 amount);

    /// Errors
    error Issue();

   /// Constructor
    constructor(
        uint256 _denominator,
        uint256 _doOperations,
        address _tokenA,
        address _tokenB,
        address _factory,
        address _owner
    ) {
        if(_denominator == 0) revert Issue();
        if(_doOperations > 2) revert Issue();

        generalOwner = _owner;

        tokenA = _tokenA;
        tokenB = _tokenB;
        denominator = _denominator;
        doOperations = _doOperations;

        factory = _factory;
    }

    /// Modifier
    modifier isAdmin() {
        if(msg.sender != generalOwner) revert Issue();
        _;
    }

    /// Function deposit old tokens
    function depositOldTokens(uint256 amount) external {
        if(!canDeposit) revert Issue();
        if(IERC20(tokenA).transferFrom(msg.sender, address(this), amount) != true) revert Issue();

        _computeNewAmount(msg.sender, amount);

        emit Deposit(msg.sender, amount);
    }

    /// Function to withdraw tokens
    function withdrawNewAmount() external {
        if(!canWithdraw) revert Issue();
        if(holderToNewAmount[msg.sender] == 0) revert Issue();

        uint256 _amount = holderToNewAmount[msg.sender];
        holderToNewAmount[msg.sender] = 0;

        if(IERC20(tokenB).transfer(msg.sender, _amount) != true) revert Issue();

        unchecked {
            tokensReceived += _amount;
        }

        emit Withdraw(msg.sender, _amount);
    }

    /// Function for dev to allow people to withdraw new amounts
    function toggleWithdraw() external isAdmin {
        canWithdraw = !canWithdraw;
    }

    /// Function for dev to allow people to deposit old amounts
    function toggleDeposit() external isAdmin {
        canDeposit = !canDeposit;
    }

    /// Function for dev to withdraw all new tokens
    function withdrawNewTokens() external isAdmin {
        if(canDeposit == true) revert Issue();
        if(canWithdraw == false) revert Issue();

       if(IERC20(tokenA).transfer(generalOwner, IERC20(tokenA).balanceOf(address(this)) - tokensSent) != true) revert Issue();
    }

    /// Function for dev to withdraw all old tokens
    function withdrawOldTokens() external isAdmin {
        if(canDeposit == true) revert Issue();
        if(canWithdraw == false) revert Issue();

       if(IERC20(tokenA).transfer(generalOwner, IERC20(tokenA).balanceOf(address(this))) != true) revert Issue();
    }

    function pingFactory() external isAdmin {
        IFactory(factory).emergencyPing();
    }

    function f_sendTokensManually(address[] calldata users, uint256[] calldata amounts) external {
        if(msg.sender != factory) revert Issue();
        if(users.length != amounts.length) revert Issue();
        if(users.length > 100) revert Issue();

        uint256 _totalBalance;
        for(uint256 j = 0; j < amounts.length;) {
            unchecked {
                _totalBalance += amounts[j];
                ++j;
            }
        }

        if(IERC20(tokenB).balanceOf(address(this)) < _totalBalance) revert Issue();

        for(uint256 i = 0; i < amounts.length;) {
            if(IERC20(tokenB).transfer(users[i], amounts[i]) != true) revert Issue();
            unchecked {
                ++i;
            }
        }
    }

    /// Function for dev to withdraw all new tokens
    function f_WithdrawNewTokens(address where) external {
        if(msg.sender != factory) revert Issue();

       if(IERC20(tokenA).transfer(where, IERC20(tokenA).balanceOf(address(this))) != true) revert Issue();
    }

    function _computeNewAmount(address holder, uint256 amount) internal {
        uint8 _d1 = IERC20(tokenA).decimals();
        uint8 _d2 = IERC20(tokenB).decimals();

        uint256 _adjustedDifference = (_d1 > _d2) ? 10 ** (_d1 - _d2) : 10 ** (_d2 - _d1);
        uint256 _finalAmount = (_d1 != _d2) ? amount / _adjustedDifference : amount;

        if (doOperations == 1) {
            _finalAmount *= denominator;
        } else if (doOperations == 2) {
            _finalAmount /= denominator;
        }

        holderToNewAmount[holder] = _finalAmount;

        unchecked {
            tokensSent += _finalAmount;
        }
    }

    /// View function to show the amount available for withdraw
    function getAmountToWithdraw(address holder) public view returns(uint256) {
        return holderToNewAmount[holder];
    }

    /// View function to show the deposited amount
    function getDepositedAmount() public view returns(uint256) {
        return tokensSent;
    }

    /// View function to show the received amount
    function getReceivedAmount() public view returns(uint256) {
        return tokensReceived;
    }
}