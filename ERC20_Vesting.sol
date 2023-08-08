//SPDX-License-Identifier: MIT


/// @title Vesting for ERC20 tokens
/// @notice Custom made smart contract to create a vesting schedule for investors
/// @author Socarde Paul


/// Solidity version
pragma solidity ^0.8.0;

/// Imports
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// ERC20 Interface
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// The Smart Contract
contract ERC20_Vesting is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    /// Variables for coin fees
    uint256 public vestingFee;
    uint256 public totalFeesForRefferals;

    /// Variables for token fees
    address public token;
    uint256 public vestingFeeVo;
    uint256 public totalFeesForRefferalsVo;

    /// Pay in coins or tokens
    bool public payInTokens;

    /// Link investors to project
    mapping(address => uint256[]) public projectToInvestors;

    /// Link investor to vesting schedule
    mapping(address => uint256[]) public addressToInvestors;

    /// Keep track of bonuses
    mapping(address => uint256) public refferalRewards;
    mapping(address => uint256) public refferalRewardsVo;

    /// Check if a deposit pinged for support
    mapping(uint256 => bool) public depositPinged;

    /// Struct for investor
    struct Investor {
        uint256[] amounts;
        uint256[] vestingPeriods;
        address tokenToReceive;
        address receiver;
        bool empty;
    }

    /// Array of investors
    Investor[] public investors;

    /// Single error to reduce gas
    error Issue();

    /// Events
    event WithdrawFromVesting(uint256 vestingId);
    event WithdrawRefferalBonus(address indexed refferal, uint256 amount);
    event WithdrawRefferalBonusVO(address indexed refferal, uint256 amount);
    event NewInvestor(uint256[] amounts, uint256[] periods, address indexed token, address indexed receiver);

    /// Constructor
    constructor() {
        _disableInitializers();
    }

    /// Initialize
    function initialize() initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();


    }

    /// Authorize upgrade (UUPS specific)
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /// Allow the smart contract to receive coins
    receive() external payable {}

    /// @dev Function to add an investor & vesting periods.
    /// @param amounts Amounts of token to receive.
    /// @param vestingPeriods Vesting periods in day.
    /// @param tokenToReceive Address of the token to be distributed;
    /// @param receiver Who will receive the tokens
    /// @param refferal Refferal that will receive 10% of a transaction if somebody is recommendit it.
    function addInvestor(
        uint256[] calldata amounts,
        uint256[] calldata vestingPeriods,
        address tokenToReceive,
        address receiver,
        address refferal
        ) external payable {
        /// Check the length of the arrays
        if(amounts.length != vestingPeriods.length) revert Issue();

        /// Maximum 5 vesting periods per investor
        if(vestingPeriods.length > 4) revert Issue();

        /// Investor should not be address(0)
        if(receiver == address(0)) revert Issue();

        /// Token to receive should not be address(0)
        if(tokenToReceive == address(0)) revert Issue();

        /// The caller can't use his own address as refferal
        if(refferal == msg.sender) revert Issue();

        /// If users needs to pay in ERC20 tokens
        if(payInTokens == true) {
         /// Msg.value should be zero
         if(msg.value != 0) revert Issue();

          /// We transfer the tokens from msg.sender to the smart contract
          if(IERC20(token).transferFrom(msg.sender, address(this), vestingFeeVo) != true) revert Issue();
           
           /// If the caller recommend a refferal
           if(refferal != address(0)) {
                /// We mark the bonus in tokens for this refferal
                _addBonusToRefferalVo(refferal, vestingFeeVo / 10);
            }
        } else if(payInTokens == false){
           /// If we take the fee in coins
           /// Msg.value should be > fee
           if(msg.value < vestingFee) revert Issue();

             /// If the caller recommend a refferal
             if(refferal != address(0)) {

                /// We mark the bonus in coins for this refferal
                _addBonusToRefferal(refferal, vestingFee / 10);
            }
        }

        /// Instance for new investor
        Investor memory newInvestor;

        /// Total amount to send to the smart contract
        uint256 _finalAmount;

        /// Iterate through the array
        for(uint256 i = 0; i < amounts.length;) {
            /// Amounts should not be zero
            if(amounts[i] == 0) revert Issue();
            /// Push the amount in the investor struct
            newInvestor.amounts[i] = amounts[i];
            /// Compute the vesting period
            uint256 _vestingPeriod = vestingPeriods[i] * 1 days;
            /// Add the vesting period
            newInvestor.vestingPeriods[i] = block.timestamp + _vestingPeriod;
            /// Compute the final amount
            _finalAmount += amounts[i];

            unchecked {
                ++i;
            }
        }

        /// Send the tokens to the smart contract
        if(IERC20(tokenToReceive).transferFrom(msg.sender, address(this),  _finalAmount) != true) revert Issue();

        /// Add variables to the investor struct
        newInvestor.tokenToReceive = tokenToReceive;
        newInvestor.receiver = receiver;

        /// Link the vesting periods to the token address
        projectToInvestors[tokenToReceive].push(investors.length);

        /// Link the vesting periods to the owner address
        addressToInvestors[msg.sender].push(investors.length);
        
        /// Push
        investors.push(newInvestor);

        emit NewInvestor(amounts, vestingPeriods, tokenToReceive, receiver);
    }

    /// @dev Function to receive the available amount from the vesting periods
    function withdrawFromVesting(uint256 vestingId) external {
        /// Empty array that will be populated with the available amounts
        uint256[] memory availableVestings;

        /// Access the investor struct in storage
        Investor storage _investor = investors[vestingId];

        /// Iterate through amounts
        for(uint256 i = 0; i < _investor.amounts.length;) {
            /// If the vesting period is < time now AND the amount is still there
            if(_investor.vestingPeriods[i] < block.timestamp && _investor.amounts[i] < 1) {
                /// Push the amount in our local array
                availableVestings[i] = _investor.amounts[i];
                /// Set the amopunt to zero in storage
                _investor.amounts[i] = 0;
            }
            unchecked {
                ++i;
            }
        }

        /// Send the tokens
        for(uint256 j = 0; j < availableVestings.length;) {
            IERC20(_investor.tokenToReceive).transfer(_investor.receiver, availableVestings[j]);
            unchecked {
                ++j;
            }
        }

        /// Check if there are tokens left
        if(_investor.amounts[_investor.amounts.length - 1] == 0) {
            /// If not, mark the vesting schedule as empty
            _investor.empty = true;
        }

        emit WithdrawFromVesting(vestingId);
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

        if(IERC20(token).transfer(msg.sender, _rewards) != true) revert Issue();

        emit WithdrawRefferalBonusVO(msg.sender, _rewards);
    }

    /// @dev Only-owner function to withdraw the fees in coins
    function withdrawFees() external onlyOwner {
        uint256 _fees = address(this).balance - totalFeesForRefferals;
         _sendCoins(owner(), _fees);
    }

    /// @dev Only-owner function to withdraw the fees in tokens
    function withdrawVoFees() external onlyOwner {
        uint256 _fees = IERC20(token).balanceOf(address(this)) - totalFeesForRefferals;
        if(IERC20(token).transfer(owner(), _fees) != true) revert Issue();
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
        uint256 newVestingFee,
        uint256 newVestingFeeVo
    ) external onlyOwner {
        vestingFee = newVestingFee;
        vestingFeeVo = newVestingFeeVo;
    }

    /// @dev Only-owner function to change the token used for fees & rewards
    function changeVoToken(address newVoToken) external onlyOwner {
        token = newVoToken;
    }

    /// @dev Withdraw ERC20 tokens in case of emergency
    function withdrawERC20tokens(address _token) external onlyOwner {
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(token).transfer(owner(), _balance);
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

    /// @dev Return all vestings linked to a project
    function getProjectToVestings(address project) public view returns(uint256[] memory) {
        return projectToInvestors[project];
    }

    /// @dev Return all vestings linked to an investor
    function getProjectToInvestors(address investor) public view returns(uint256[] memory) {
        return addressToInvestors[investor];
    }

}