// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @author Socarde Paul
 * @title Bid Setter.
 * @notice Smart Contract to manage the bids for different market 
 *         items on an NFT marketplace.
 */


/** IMPORTS */
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/** INTERFACES */
interface IMarketPlace {
    function getMarketItemDetails(
        uint256 id
    )
    external
    view
    returns (
        uint256,
        uint256,
        uint256,
        address,
        address,
        bool,
        bool,
        bool
    );
    function acceptBid(
        uint256 id,
        address receiver
    )
    external;
    function getMarketItemsLength() external view returns (uint256);
}

contract BidSettings is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    
    /** ADDRESS */
    IMarketPlace public marketPlace;

    /** BOOL */
    bool private paused;

    /** STRUCT */
    struct Bid {
        uint256 marketItem;
        uint256 bid;
        address bidder;
        bool accepted;
        bool closed;
    }

    /** Array of bids */
    Bid[] public bids;

    /** MAPPINGS */
    mapping(uint256 => uint256[]) public marketItemBids; // Market Item id -> array of bid ids
    mapping(address => uint256[]) public myBids; // Id -> array of bid ids

    /** EVENTS */
    event CreateBid(
        uint256 marketItem,
        uint256 bid,
        address bidder
    );
    event WithdrawBid(
        uint256 bidId
    );
    event AcceptBid(
        uint256 bidId
    );

    /** MODIFIERS */
    modifier isPaused() {
        require(
            !paused,
            "BidSettings::Contract is paused!"
        );

        _;
    }

    /** UUPS FUNCTIONS */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _marketPlace
    ) initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        marketPlace = IMarketPlace(_marketPlace);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /** EXTERNAL FUNCTIONS */
    function togglePause() external onlyOwner {
        paused = !paused;
    }

    /**
     * @dev Function to change the address of the marketplace
     *      for which we manage the bids.
     * @param _newMarketPlace The new address of the marketplace.
     */
    function changeMarketPlace(
        address _newMarketPlace
    )
    external
    onlyOwner
    {
        marketPlace = IMarketPlace(_newMarketPlace);
    }

    /**
     * @dev Function to create a bid for a market item.
     * @param marketItem For which item do we want to bid?
     * @param bid How much do we want to bid (in wei)?
     */
    function createBid(
        uint256 marketItem,
        uint256 bid
    ) 
    external
    payable
    nonReentrant
    isPaused
    {
        uint256 _itemsLength = marketPlace.getMarketItemsLength();

        require(
            marketItem < _itemsLength,
            "BidSettings::Invalid item!"
        );

        (
            ,
            , 
            uint256 _bidEndDate,
            , 
            ,
            bool _openForBids, 
            bool _closed, 
            bool _sold
        ) = marketPlace.getMarketItemDetails(marketItem);

        require(
            block.timestamp <= _bidEndDate,
            "BidSettings::Can't bid anymore for this item!"
        );

        require(
            _openForBids,
            "BidSettings::This item is not on auction!"
        );

        require(
            !_closed,
            "BidSettings::This item is not on the market!"
        );

        require(
            !_sold,
            "BidSettings::Item already sold!"
        );

        require(
            msg.value >= bid,
            "BidSettings::Can't send the bid!"
        );

        marketItemBids[marketItem].push(bids.length);
        myBids[msg.sender].push(bids.length);

        bids.push(
            Bid(
                marketItem,
                bid,
                msg.sender,
                false,
                false
            )
        );

        emit CreateBid(marketItem, bid, msg.sender);
    }

    /**
     * @dev Function to withdraw a bid for a market item.
     * @param bidId Which bid do we want to withdraw?
     */
    function withdrawBid(
        uint256 bidId
    )
    external
    nonReentrant()
    isPaused()
    {
        require(
            bidId < bids.length,
            "BidSettings::Invalid bid!"
        );

        Bid storage _bid = bids[bidId];

        require(
            msg.sender == _bid.bidder,
            "BidSettings::Not bid owner!"
        );

        require(
            !_bid.accepted,
            "BidSettings::Bid already accepted!"
        );

        require(
            !_bid.closed,
            "BidSettings::Bid already closed!"
        );

        uint256 _amount = _bid.bid;
        address _bidder = _bid.bidder;

        _bid.closed = true;
        _bid.bid = 0;

        safeSendPayment(_amount, _bidder);

        emit WithdrawBid(bidId);
    }

    /**
     * @dev Function to accept a bid for a market item.
     * @param bidId Which bid do we want to accept?
     * @notice Can be called only by the market item's owner/seller.
     */
    function acceptBid(
        uint256 bidId
    )
    external
    nonReentrant()
    isPaused()
    {
        require(
            bidId < bids.length,
            "BidSettings::Invalid bid!"
        );

        Bid storage _bid = bids[bidId];

        (
            ,
            ,
            ,
            address _seller, 
            ,
            ,
            bool _closed, 
            bool _sold
        ) = marketPlace.getMarketItemDetails(_bid.marketItem);

        require(
            msg.sender == _seller,
            "BidSettings::You are not the owner of this item!"
        );

        require(
            !_bid.accepted,
            "BidSettings::Bid already accepted!"
        );

        require(
            !_bid.closed,
            "BidSettings::Bid already closed!"
        );

        require(
            !_closed,
            "BidSettings::Item closed!"
        );

        require(
            !_sold,
            "BidSettings::Item already sold!"
        );

        _bid.accepted = true;

        safeSendPayment(
            _bid.bid,
            _seller
        );

        marketPlace.acceptBid(
            _bid.marketItem,
            _bid.bidder
        );

        emit AcceptBid(bidId);
    }

    /** Receive ETH */
    receive() external payable {}

    /** INTERNAL FUNCTIONS */
    
    /**
     * @dev Function to send ETH in a safe manner.
     * @param amount The amount in wei.
     * @param receiver The receiver's address.
     */
    function safeSendPayment(
        uint256 amount,
        address receiver
    )
    internal
    {
        (bool _sent, ) = receiver.call{value: amount}("");
        
        require(
            _sent,
            "BidSettings::Can't transfer ETH!"
        );
    }
}