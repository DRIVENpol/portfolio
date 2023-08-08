// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @author Socarde Paul
 * @title NFT Marketplace Smart Contract
 */

/** IMPORTS */
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/** INTERFACES */
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract NFT_MarketPlace is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    /** UINT */
    uint256 public totalItemsSold;

    /** ADDRESS */
    address public bidSettings;

    /** BOOL */
    bool private paused;

    /** STRUCT */
    struct MarketItem {
        uint256 nftId;
        uint256 price;
        uint256 bidEndDate;
        address seller;
        address collection;
        bool openForBids;
        bool closed;
        bool sold;
    }

    /** Array of market items */
    MarketItem[] public marketItems;

    /** MAPPINGS */
    mapping(address => uint256[]) public myListedItems; // Address -> Market item ids
    mapping(address => uint256[]) public collectionItems; // Address -> Market item ids

    /** EVENTS */
    event ListNft(
        uint256 id,
        uint256 price,
        uint256 bidEndDate,
        address collection,
        bool openForBids
    );
    event CreateAuction(
        uint256 id,
        uint256 periodInDays
    );
    event ExtendAuction(
        uint256 id,
        uint256 extendPeriodInDays
    );
    event BuyMarketItem(
        uint256 id
    );
    event CloseMarketItem(
        uint256 id
    );
    event CloseAuction(
        uint256 id
    );
    event AcceptBidForMarketItem(
        uint256 id
    );

    /** MODIFIERS */
    modifier onlyBidSettings() {
        require(
            msg.sender == bidSettings,
            "Marketplace::Not bidSettings!"
        );

        _;
    }

    modifier isPaused() {
        require(
            !paused,
            "Marketplace::Contract is paused!"
        );

        _;
    }

    /** UUPS FUNCTIONS */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bidSettings
    ) initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        bidSettings = _bidSettings;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /** EXTERNAL FUNCTIONS */

    /**
     * @dev Function to pause/unpause the smart contract
     */
    function togglePause() external onlyOwner {
        if(paused) {
            paused = false;
        } else {
            paused = true;
        }
    }

    /**
     * @dev Function to change 'bidSettings' address.
     * @param _newBidSettings The address of the new BidSettings smart contract.
     * @notice BidSettings is the smart contract that manage the bids for a market item.
     */
    function changeBidSettings(
        address _newBidSettings
    )
    external
    onlyOwner
    {
        bidSettings = _newBidSettings;
    }

    /**
     * @dev Function to list and NFT for sale as a market item.
     * @param id The id of the NFT we want to sell.
     * @param price The price (in wei) of the NFT.
     * @param bidEndDate The end date of an auction. If 'openForBids'
     *                   is "FALSE", the value of "bidEndDate' will be zero.
     * @param collection The collection the NFT we want to list.
     * @param openForBids Do we want to open an auction for that item?
     */
    function listNftForSale(
        uint256 id,
        uint256 price,
        uint256 bidEndDate,
        address collection,
        bool openForBids
    )
    external
    nonReentrant
    isPaused
    {
        IERC721(collection).transferFrom(
            msg.sender,
            address(this),
            id
        );

        uint256 _bidEndDate;

        if(openForBids) {
            _bidEndDate = block.timestamp + (bidEndDate * 1 days);
        }
        
        myListedItems[msg.sender].push(marketItems.length);
        collectionItems[collection].push(marketItems.length);

        marketItems.push(
            MarketItem(
                id, 
                price,
                _bidEndDate,
                msg.sender, 
                collection, 
                openForBids,
                false, 
                false
                )
        );

        emit ListNft(id, price, bidEndDate, collection, openForBids);
    }

    /**
     * @dev Function to buy a market item (NFT).
     * @param id The id of the market item.
     */
    function buyMarketItem(
        uint256 id
    )
    external
    payable
    nonReentrant
    isPaused
    {
        require(
            id < marketItems.length,
            "Marketplace::Not a market item!"
        );

        MarketItem storage _item = marketItems[id];

        require(
            !_item.sold,
            "Marketplace::Item already sold!"
        );

        require(
            !_item.openForBids,
            "Marketplace::This item is on auction!"
        );

        require(
            !_item.closed,
            "Marketplace::Not for sale anymore!"
        );

        require(
            msg.value >= _item.price,
            "Marketplace::Please pay for your NFT!"
        );

        _item.sold = true;

        IERC721(_item.collection).transferFrom(
            address(this),
            msg.sender,
            id
        );

        safeSendPayment(
            _item.price,
            _item.seller
        );

        unchecked {
            ++totalItemsSold;
        }

        emit BuyMarketItem(id);
    }

    /**
     * @dev Function to withdraw an item (NFT) from the market.
     * @param id The id of the market item.
     */
    function closeMarketItem(
        uint256 id
    )
    external
    nonReentrant
    isPaused
    {
        require(
            id < marketItems.length,
            "Marketplace::Not a market item!"
        );

        MarketItem storage _item = marketItems[id];

        require(
            msg.sender == _item.seller,
            "Marketplace::You are not the owner of this item!"
        );

        require(
            !_item.sold,
            "Marketplace::Item already sold!"
        );

        require(
            !_item.openForBids,
            "Marketplace::End the auction first!"
        );

        require(
            !_item.closed,
            "Marketplace::Not on sale anymore!"
        );

        _item.closed = true;

        IERC721(_item.collection).transferFrom(
            address(this),
            msg.sender,
            id
        );

        emit CloseMarketItem(id);
    }

    /**
     * @dev Function to create an auction for a listed a market item (NFT).
     * @param id The id of the market item.
     * @param periodInDays For how many days the auction will be open (starting from now)?
     */
    function createAuction(
        uint256 id,
        uint256 periodInDays
    )
    external
    nonReentrant
    isPaused
    {
        require(
            id < marketItems.length,
            "Marketplace::Not a market item!"
        );

        uint256 _periodInDays = block.timestamp + (periodInDays * 1 days);

        MarketItem storage _item = marketItems[id];

        require(
            msg.sender == _item.seller,
            "Marketplace::You are not the owner of this item!"
        );

        require(
            !_item.sold,
            "Marketplace::Item already sold!"
        );

        require(
            !_item.openForBids,
            "Marketplace::Item already on auction!"
        );

        require(
            !_item.closed,
            "Marketplace::Not on sale anymore!"
        );

        _item.openForBids = true;

        unchecked {
            _item.bidEndDate += _periodInDays;
        }

        emit CreateAuction(id, periodInDays);
    }

    /**
     * @dev Function to extend the auction period for a market item.
     * @param id The id of the market item.
     * @param extendPeriodInDays With how many days do we want to extend the period?
     */
    function extendBidTime(
        uint256 id,
        uint256 extendPeriodInDays
    )
    external
    nonReentrant
    isPaused
    {
        require(
            id < marketItems.length,
            "Marketplace::Not a market item!"
        );

        uint256 _extendPeriodInDays = extendPeriodInDays * 1 days;

        MarketItem storage _item = marketItems[id];

        require(
            msg.sender == _item.seller,
            "Marketplace::You are not the owner of this item!"
        );

        require(
            !_item.sold,
            "Marketplace::Item already sold!"
        );

        require(
            _item.openForBids,
            "Marketplace::Item is not on auction!"
        );

        require(
            !_item.closed,
            "Marketplace::Not on sale anymore!"
        );

        if (block.timestamp < _item.bidEndDate) {
            unchecked {
                _item.bidEndDate += _extendPeriodInDays;
            }
        } else if (block.timestamp >= _item.bidEndDate) {
            unchecked {
                _item.bidEndDate += (block.timestamp + _extendPeriodInDays);
            }
        }

        emit ExtendAuction(id, extendPeriodInDays);
    }

    /**
     * @dev Function to close the auction for a market item.
     * @param id The id of the market item.
     */
    function closeBidding(
        uint256 id
    )
    external
    nonReentrant
    isPaused
    {
        require(
            id < marketItems.length,
            "Marketplace::Not a market item!"
        );

        MarketItem storage _item = marketItems[id];

        require(
            msg.sender == _item.seller,
            "Marketplace::Not item owner!"
        );

        require(
            _item.openForBids,
            "Marketplace::Item not opened to auction!"
        );
        
        _item.openForBids = false;

        emit CloseAuction(id);
    }

    /**
     * @dev Function to accept a bid for a market item.
     * @param id The id of the market item.
     * @param receiver Where do we transfer the market item after the bid
     *                 was sent to the seller?
     * @notice This function is called ONLY by the 'bidSettings' smart contract.
     */
    function acceptBid(
        uint256 id,
        address receiver
    )
    external
    onlyBidSettings
    isPaused
    {
        require(
            id < marketItems.length,
            "Marketplace::Not a market item!"
        );

        MarketItem storage _item = marketItems[id];

        require(
            _item.openForBids,
            "Marketplace::Item not opened to auction!"
        );

        require(
            !_item.sold,
            "Marketplace::Item already sold!"
        );

        require(
            !_item.closed,
            "Marketplace::Item closed!"
        );

        _item.openForBids = false;
        _item.sold = true;

        IERC721(_item.collection).transferFrom(
            address(this),
            receiver,
            id
        );

        emit AcceptBidForMarketItem(id);
    }

    /** Receive ETH */
    /**
     * @dev Function to receive ETH / native tokens
     */
    receive() external payable {}

    /** EXTERNAL VIEW */

    /**
     * @dev Function to fetch the details of a market item.
     * @return '_item.nftId' - The NFT id (type: uint256).
     * @return '_item.price' - The NFT price (type: uint256).
     * @return '_item.bidEndDate' - The end date of the auction,if is the case (type: uint256).
     * @return '_item.seller' - The seller of the NFT (type: address).
     * @return '_item.collection' - The collection address (type: address).
     * @return '_item.openForBids' - If there is a live auction for the item (type: bool).
     * @return '_item.closed' - If the market item was removed by the owner (type: bool).
     * @return '_item.sold' - If the item was sold (type: bool).
     */
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
    )
    {
        MarketItem memory _item = marketItems[id];

        return(
            _item.nftId,
            _item.price,
            _item.bidEndDate,
            _item.seller,
            _item.collection,
            _item.openForBids,
            _item.closed,
            _item.sold
        );
    }

    /**
     * @dev Function to return the number of listed NFTs of a user.
     * @param user For which user do we want to return that.
     */
    function getMyListedItemsLength(
        address user
    )
    external
    view
    returns (uint256) {
        return myListedItems[user].length;
    }

    /**
     * @dev Function to return the number of listed NFTs of a collection.
     * @param collection For which collection do we want to return that.
     */
    function getCollectionItemsLength(
        address collection
    )
    external
    view
    returns (uint256) {
        return collectionItems[collection].length;
    }

    /**
     * @dev Function to return the number of listed NFTs.
     */
    function getMarketItemsLength() external view returns (uint256) {
        return marketItems.length;
    }

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
            "Marketplace::Can't transfer ETH!"
        );
    }
}