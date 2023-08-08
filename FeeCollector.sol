//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";

interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/**
 * @title Pay Monthly Subscription
 * @notice This smart contract is designed to retrieve the real-time price of the token used for payments
 * @author Socarde Paul
 */

contract FeeCollector is Ownable {

    /// Fees in USD
    uint256 public feePerMonth = 995; // 99,5
    uint256 public feePerYear = 89; // 8,9

    /// Analytics
    uint256 public totalPayments;
    uint256 public totalPaymentsInBnb;
    uint256 public totalAmountPaidInBnb;

    /// Hot wallet address
    address private hotWallet;

    /// Payment receiver
    address public paymentRecipient;

    /// Amount to pay in tokens for 30 days
    mapping(address => uint256) public amountToPay30;

    /// Amount to pay in tokens for 365 days
    mapping(address => uint256) public amountToPay365;

    /// Next payroll
    mapping(address => uint256) public nextPayroll;

    /// Mappings for analytics
    mapping(address => uint256) public paymentsByToken;
    mapping(address => uint256) public totalAmountPaidByToken;

    /// Token supported for payments
    /// 0 - not supported; 1 - supported
    /// We do not use boolean variables because we want to save gas
    mapping(address => uint256) public tokenSupported;

    /// Events
    event NewPrice30(address indexed token, uint256 price);
    event NewPrice365(address indexed token, uint256 price);
    event UserPaid(address indexed user, uint256 period);

    /// Constructor
    constructor() {
        // We whitelist address(0)
        // When this address is used, the payment
        // will be made in coins (BNB, ETH)
        tokenSupported[address(0)] = 1;
    }
    
    /// Receive payments in BNB
    receive() external payable {}


    /// *********************************************
    /// *************** PRICE ORACLE  ***************
    /// *********************************************


    /// @dev Set how much somebody needs to pay in different tokens
    ///      for the monthly subscription
    /// @param token - Token used for payments
    /// @param newPrice - The amount that needs to be paid
    function setPrice30Days(address token, uint256 newPrice) external {
        require(newPrice > 0, "Ooops!");
        require(msg.sender == hotWallet, "Ooops!");
        require(tokenSupported[token] == 1, "Token not supported!");
        amountToPay30[token] = newPrice;

        emit NewPrice30(token, newPrice);
    }

    /// @dev Set how much somebody needs to pay in different tokens
    ///      for the anually subscription
    /// @param token - Token used for payments
    /// @param newPrice - The amount that needs to be paid
    function setPrice365Days(address token, uint256 newPrice) external {
        require(newPrice > 0, "Ooops!");
        require(msg.sender == hotWallet, "Ooops!");
        require(tokenSupported[token] == 1, "Token not supported!");
        amountToPay365[token] = newPrice;

        emit NewPrice365(token, newPrice);
    }


    /// ***************************************************
    /// *************** INTERNAL FUNCTIONS  ***************
    /// ***************************************************


    /// @dev Internal function to compute how many tokens needs to be paid
    function computeAmountToPay(address token, bool monthly) internal view returns(uint256 _toPay) {
        if(monthly) {
            return amountToPay30[token];
        } else {
            return amountToPay365[token];
        }
    }

    /// @dev Internal function to add a payment
    function addPayment(address user, bool monthly) internal {
        uint256 _endDate = monthly ? 30 days : 365 days;
        uint256 _period = monthly ? 30 : 365;

        if(block.timestamp < nextPayroll[user]) {
            nextPayroll[user] += _endDate;
        } else {
            nextPayroll[user] = block.timestamp + _endDate;
        }

        emit UserPaid(user, _period);
    }


    /// *************************************************
    /// *************** PUBLIC FUNCTIONS  ***************
    /// *************************************************


    /// @dev Function to pay the subscription
    /// @param token - The token that will be used to pay the subscription
    /// @param monthly - Choose if we pay the monthly subscription or annually subscription
    function paySubscription(address token, bool monthly) external payable {
        require(tokenSupported[token] == 1, "Not supported token!");

        uint256 _amountToPay = computeAmountToPay(token, monthly);

        if(token == address(0)) {
            require(msg.value >= _amountToPay, "Failed Transaction :: BNB");
            unchecked {
                ++totalPaymentsInBnb;
                totalAmountPaidInBnb += _amountToPay;
            }
        } else {
            require(IToken(token).transferFrom(msg.sender, address(this), _amountToPay),
            "Failed Transaction :: ERC20");

            unchecked {
                ++paymentsByToken[token];
                totalAmountPaidByToken[token] += _amountToPay;
            }
        }

        addPayment(msg.sender, monthly);

        unchecked {
            ++totalPayments;
        }
    }


    /// *****************************************************
    /// *************** ONLY OWNER FUNCTIONS  ***************
    /// *****************************************************


    /// @dev Function to manually add a payment
    function manualPaymentForUser(address user, bool monthly) external onlyOwner {
        addPayment(user, monthly);
    }

    /// @dev Function to manually add a payment for multiple users
    function manualPaymentForMultipleUsers(
        address[] calldata users,
        bool[] calldata monthly
        ) external onlyOwner {
        require(users.length == monthly.length, "Invalid length for parameters!");
        for(uint256 i = 0; i < users.length;) {
            addPayment(users[i], monthly[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Function to change the address of the hot wallet
    function changeHotWallet(address newHotWallet) external onlyOwner {
        hotWallet = newHotWallet;
    }

    /// @dev Function to change the payment receiver
    function changePaymentRecipient(address newPaymentRecipient) external onlyOwner {
        paymentRecipient = newPaymentRecipient;
    }

    /// @dev Function to change the fee per month - USD
    function changeFeePerMonth(uint256 newFeePerMonth) external onlyOwner {
        feePerMonth = newFeePerMonth;
    }

    /// @dev Function to change the fee per year - USD
    function changeFeePerYear(uint256 newFeePerYear) external onlyOwner {
        feePerYear = newFeePerYear;
    }

    /// @dev Function to add supported tokens
    function addSupportedToken(address newToken) external onlyOwner {
        require(tokenSupported[newToken] == 0, "Token already supported!");
        tokenSupported[newToken] = 1;
    }

    /// @dev Function to remove supported tokens
    function removeSupportedToken(address token) external onlyOwner {
        require(tokenSupported[token] == 1, "Token already not-supported!");
        tokenSupported[token] = 0;        
    }

    /// @dev Function to withdraw BNB payments
    function withdrawBnbPayments() external onlyOwner {
        uint256 _amount = address(this).balance;
        (bool _sent, ) = paymentRecipient.call{value: _amount}("");
        require(_sent, "Failed Transaction!");
    }

    /// @dev Function to withdraw ERC20 token payments
    function withdrawTokenPayments(address token) external onlyOwner {
        require(tokenSupported[token] == 1, "Not supported token!");
        IToken _token = IToken(token);
        uint256 _amount = _token.balanceOf(address(this));
        require(_token.transfer(paymentRecipient, _amount), "Failed Transaction :: ERC20");
    }


    /// ***********************************************
    /// *************** READ FUNCTIONS  ***************
    /// ***********************************************


    /// @dev Function to read how much an user needs to pay in tokens [FOR UI]
    function getAmountToPay(address token, bool monthly) public view returns(uint256 _price) {
        if(monthly) {
            _price = amountToPay30[token];
        } else {
            _price = amountToPay365[token];
        }
    }

    /// @dev Function to fetch the end date of the subscription [FOR UI]
    function getNextPayroll(address user) public view returns(uint256 _nextPayroll) {
        _nextPayroll = nextPayroll[user];
    }

    /// @dev Function to fetch the fee per month and the fee per year [FOR UI]
    function getFees() public view returns(uint256 _perMonth, uint256 _perYear) {
        _perMonth = feePerMonth;
        _perYear = feePerYear;
    }

    /// @dev Function to fetch the total payments
    function getTotalPayments() public view returns(uint256 _totalPayments) {
        _totalPayments = totalPayments;
    }

    /// @dev Function to fetch the analytics for BNB payments
    function getAnalyticsForBnbPayments() public view returns(uint256 _totalPaymentsInBnb, uint256 _totalAmountPaidInBnb) {
        _totalPaymentsInBnb = totalPaymentsInBnb;
        _totalAmountPaidInBnb = totalAmountPaidInBnb;
    }

    /// @dev Function to fetch the analytics for ERC20 payments
    function getAnalyticsForTokenPayments(address token) public view returns(uint256 _totalPaymentsInToken, uint256 _totalAmountPaidInToken) {
        _totalPaymentsInToken = paymentsByToken[token];
        _totalAmountPaidInToken = totalAmountPaidByToken[token];
    }
}