/**
 * @title Subscription ticket as NFT
 * @author Socarde Paul
 */

// SPDX-License-Identifier: MIT

/** PRAGMA VERSION */
pragma solidity ^0.8.0;

/** IMPORTS */
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./Ownable.sol";

/** INTERFACES */
interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract FlightClubSubscription is ERC721, Ownable {

    /** VARIABLES */
    uint256 private id; // Current NFT Id

    uint256 public pricePerMonth = 50 ether; // Price of subscription
    string public uri; // Collection's URI

    address public BUSD; // Token used for payments
    address[] public uniqueUsers; // Array of unique users

    /** MAPPINGS */
    mapping(address => uint256) public endDate; // End date for user's subscription
    mapping(address => bool) private isKicked; // User is kicked?
    mapping(address => bool) private isUniqueUser; // User is unique?
    mapping(address => uint256) private userIndex; // Index of the user in the 'uniqueUsers' array

    /** EVENTS */
    event PaidSubscription(
        uint256 period,
        address indexed user
    );
    event KickUser(
        address indexed user
    );

    /** CONSTRUCTOR */
    constructor(
        string memory _uri,
        address _busd
    ) ERC721(
        "NFT Club Subscription", 
        "NFT"
        ) 
    {
        uri = _uri;
        BUSD = _busd;
    }

    /** RECEIVE FUNCTION */
    receive() external payable {}

    /** EXTERNAL FUNCTIONS */

    /**
     * @dev Function to pay the subscription using stable coins.
     * @param period Period of subscription.
     */
    function paySubscription(
        uint256 period
    )
    external
    payable 
    {
        require(
            IToken(BUSD).transferFrom(
                msg.sender,
                address(this),
                period * pricePerMonth
            ),
            "Can't pay the subscription!"
        );
        
        _paySubscription(period, msg.sender);
    }

    /**
     * @dev Function ti give subscription for free. Can be called only by the owner.
     * @param period Period of subscription.
     * @param user User that will receive the subscription.
     */
    function giveSubscription(
        uint256 period,
        address user
    )
    external
    onlyOwner
    {
        _paySubscription(period, user);
    }

    /**
     * @dev Function to change the settins of the smart contract.
     * @param newPricePerMonth The new monthly price for subscription.
     * @param newUri The new URI for the NFT collection.
     */
    function changeSettings(
        uint256 newPricePerMonth,
        string calldata newUri
    )
    external
    onlyOwner
    {
        pricePerMonth = newPricePerMonth;
        uri = newUri;
    }

    /**
     * @dev Function to withdraw the BNB from the smart contract;
     */
    function withdrawBnbPayments() external onlyOwner {
        uint256 _amount = address(this).balance;
        (bool _sent, ) = getOwner().call{value: _amount}("");
        require(_sent, "Failed Transaction!");
    }

    /**
     * @dev Function to withdraw ERC-20 tokens from the smart contract.
     */
    function withdrawToken(address token) external onlyOwner {
        IToken _token = IToken(token);
        uint256 _amount = _token.balanceOf(address(this));
        require(_token.transfer(getOwner(), _amount), "Failed Transaction :: ERC20");
    }

    /**
     * @dev Function to kick an user. Can be called by anybody.
     * @notice Can't execute if the user have an active subscription.
     * @param user The user that we want to kick.
     */
    function kickUser(
        address user
    )
    external 
    {
        require(
            !isKicked[user],
            "User already kicked!" 
        );

        isKicked[uniqueUsers[userIndex[user]]] = true;

        _removeUser(userIndex[user]);

        emit KickUser(user);
    }

    /** PUBLIC FUNCTIONS */

    /**
     * @dev Function to return 'True' if the user have a subscription NFT &
     *      a paid subscription.
     */
    function isValidSubscription(
        address user
    )
    public
    view
    returns (bool) {
        if (
            _checkPaidSubscription(user) &&
            _checkBalance(user)
        ) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Function to display if a user is kicked or not. 
     */
    function checkKickedUser(
        address user
    )
    public
    view
    returns (bool) {
        if(isKicked[user] == true) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Return the same URI for each token.
     */
   function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        return string(abi.encodePacked(uri));
    }

    /** INTERNAL FUNCTIONS */

    /**
     * @dev Internal function to pay the subscription.
     * @notice If the user have an active subscription we prolong it.
     *         If the user's subscription expired we start a new subscription.
     */
    function _paySubscription(
        uint256 period,
        address user
    )
    internal
    {
        uint256 _period = period * 30 days;

        if (block.timestamp >= endDate[user]) {
            uint256 _newEndDate = block.timestamp + _period;

            endDate[user] = _newEndDate;
        } else if(block.timestamp < endDate[user]) {
            unchecked {
                endDate[user] += _period;
            }
        }

        if(balanceOf(user) == 0) {
            _mintSubscriptionNft(user);
        }

        if(isKicked[user] == true) {
            isKicked[user] = false; 
        }

        if(isUniqueUser[user] == false) {
            _addUser(user);
        }

        emit PaidSubscription(period, user);
    }

    /**
     * @dev Function to add an user to 'uniqueUsers' array.
     */
    function _addUser(
        address user
    )
    internal
    {
        isUniqueUser[user] = true;
        userIndex[user] = uniqueUsers.length;
        uniqueUsers.push(user);
    }

    /**
     * @dev Function to remove an user from 'uniqueUsers' array.
     */
    function _removeUser(
        uint256 index
    )
    internal
    {
        isUniqueUser[uniqueUsers[index]] = false;
        userIndex[uniqueUsers[uniqueUsers.length - 1]] = index;
        uniqueUsers[index] = uniqueUsers[uniqueUsers.length - 1];
        uniqueUsers.pop();
    }

    /**
     * @dev Internal function that returns 'True' if the user have an active subscription.
     * @param user User that we are checking.
     */
    function _checkPaidSubscription(
        address user
    )
    internal
    view
    returns (bool)
    {
        if (
            block.timestamp <= endDate[user]
        ) {
            return true;
        } else {
            return false;
        }
    }

   /**
     * @dev Internal function that returns 'True' if the user have one subscription NFT.
     * @param user User that we are checking.
     */
    function _checkBalance(
        address user
    )
    internal
    view
    returns (bool)
    {
        if (balanceOf(user) == 1) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Internal function to mint a subscription NFT to an user.
     */
    function _mintSubscriptionNft(
        address receiver
    )
    internal 
    {
        _mint(receiver, id);
        unchecked {
            ++id;
        }
    }

    /**
     * @dev Disable the transfer function so if somebody is hacked the subscription NFT can't 
     *      be transferred
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual override {
        revert("Can't transfer the subscription NFT!");
    }
}