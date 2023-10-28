
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @author Rev3al LLC
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
interface IERC2981 {
    /// @notice Called with the sale price to determine how much royalty
    //          is owed and to whom.
    /// @param _tokenId - the NFT asset queried for royalty information
    /// @param _salePrice - the sale price of the NFT asset specified by _tokenId
    /// @return receiver - address of who should be sent the royalty payment
    /// @return royaltyAmount - the royalty payment amount for _salePrice
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (
        address receiver,
        uint256 royaltyAmount
    );
}
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

contract MarketPlace is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    /** UINT */
    uint256 public totalItemsSold;

    /** ADDRESS */
    address public bidSettings;

    /** Royalty interface */
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    /** BOOL */
    bool private paused;

    uint8 private constant OPEN_FOR_BIDS_FLAG = 1 << 0; // 00000001
    uint8 private constant CLOSED_FLAG = 1 << 1; // 00000010
    uint8 private constant SOLD_FLAG = 1 << 2; // 00000100

    /** STRUCT */
    struct MarketItem {
        uint256 nftId;
        uint256 price;
        uint256 bidEndDate;
        address seller;
        address collection;
        // bool openForBids;
        // bool closed;
        // bool sold;
        uint8 flags;
    }

    /** Array of market items */
    MarketItem[] public marketItems;

    /** MAPPINGS */
    mapping(address => uint256[]) public myListedItems; // Address -> Market item ids
    mapping(address => uint256[]) public collectionItems; // Address -> Market item ids

    /** CUSTOM ERRORS */
    error InvalidMarketItem(uint256 id);
    error NotBidSettings(address caller);
    error ContractIsPaused(bool paused);
    error NotValidAddress(address addr);
    error NotEnoughFunds(uint256 amount);


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
    event ChangePrice(
        uint256 id, 
        uint256 newPrice
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
    /** 
     * @dev Throws if called by any account other than the 'bidSettings' smart contract.
     */
    modifier onlyBidSettings() {
        if(msg.sender != bidSettings) {
            revert NotBidSettings(msg.sender);
        }

        _;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    modifier isPaused() {
        if(paused) {
            revert ContractIsPaused(paused);
        }

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
        __Ownable_init(msg.sender);
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
        paused = !paused;
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
        if(_validateAddress(_newBidSettings) == false) {
            revert NotValidAddress(_newBidSettings);
        }

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
        uint8 _flags = 0;

        if (openForBids) {
            _bidEndDate = block.timestamp + (bidEndDate * 1 days);
            _flags |= OPEN_FOR_BIDS_FLAG;
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
                _flags
            )
        );

        emit ListNft(id, price, bidEndDate, collection, openForBids);
    }


    /**
     * @dev Function to buy a market item (NFT).
     * @param id The id of the market item.
     */
    function buyMarketItem(uint256 id) 
        external 
        payable 
        nonReentrant 
        isPaused 
    {

        MarketItem storage _item = marketItems[id];

        bool _valid = _validateLength(id) &&
            _validateSold(_item.flags) &&
            _validateClosed(_item.flags) &&
            !_validateOpenForBids(_item.flags);

        if(_valid == false) {
            revert InvalidMarketItem(id);
        }

        if(msg.value < _item.price) {
            revert NotEnoughFunds(_item.price);
        }

        _item.flags |= SOLD_FLAG;

        IERC721(_item.collection).transferFrom(
            address(this),
            msg.sender,
            _item.nftId 
        );

        if(_checkRoyalties(_item.collection) == false) {
            _safeSendPayment(
                _item.price,
                _item.seller
            );

            unchecked {
                ++totalItemsSold;
            }

            emit BuyMarketItem(id);

            return;
        } else {
            (address _royaltyReceiver, uint256 _royaltyAmount) = IERC2981(_item.collection).royaltyInfo(
                _item.nftId,
                _item.price
            );

            _safeSendPayment(
                _royaltyAmount,
                _royaltyReceiver
            );

            _safeSendPayment(
                _item.price - _royaltyAmount,
                _item.seller
            );

            unchecked {
                ++totalItemsSold;
            }

            emit BuyMarketItem(id);

            return;
        }
    }

    /**
     * @dev Function to withdraw an item (NFT) from the market.
     * @param id The id of the market item.
     */
    function closeMarketItem(uint256 id)
        external
        nonReentrant
        isPaused
    {

        MarketItem storage _item = marketItems[id];

        bool _valid = _validateLength(id) &&
            _validateOwner(msg.sender, _item.seller) &&
            _validateSold(_item.flags) &&
            _validateClosed(_item.flags) &&
            !_validateOpenForBids(_item.flags);

        if(_valid == false) {
            revert InvalidMarketItem(id);
        }

        _item.flags |= CLOSED_FLAG;

        IERC721(_item.collection).transferFrom(
            address(this),
            msg.sender,
            _item.nftId
        );

        emit CloseMarketItem(id);
    }


    function changePrice(uint256 id, uint256 newPrice)
        external
        nonReentrant
        isPaused
    {

        MarketItem storage _item = marketItems[id];

        bool _valid = _validateLength(id) &&
            _validateOwner(msg.sender, _item.seller)&&
            _validateSold(_item.flags) &&
            _validateClosed(_item.flags);

        if(_valid == false) {
            revert InvalidMarketItem(id);
        }

        _item.price = newPrice;
    }


    /**
     * @dev Function to create an auction for a listed a market item (NFT).
     * @param id The id of the market item.
     * @param periodInDays For how many days the auction will be open (starting from now)?
     */
    function createAuction(uint256 id, uint256 periodInDays)
        external
        nonReentrant
        isPaused
    {
        MarketItem storage _item = marketItems[id];

        uint256 _periodInDays = block.timestamp + (periodInDays * 1 days);

        bool _valid = _validateLength(id) &&
            _validateOwner(msg.sender, _item.seller) &&
            _validateSold(_item.flags) &&
            !_validateOpenForBids(_item.flags) &&
            _validateClosed(_item.flags);

        if(_valid == false) {
            revert InvalidMarketItem(id);
        }

        _item.flags |= OPEN_FOR_BIDS_FLAG;

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
function extendBidTime(uint256 id, uint256 extendPeriodInDays)
    external
    nonReentrant
    isPaused
{

    MarketItem storage _item = marketItems[id];
    uint256 _extendPeriodInDays = extendPeriodInDays * 1 days;

    bool _valid = _validateLength(id) &&
        _validateOwner(msg.sender, _item.seller) &&
        _validateSold(_item.flags) &&
        _validateOpenForBids(_item.flags) &&
        _validateClosed(_item.flags);

    if(_valid == false) {
        revert InvalidMarketItem(id);
    }

    if (block.timestamp < _item.bidEndDate) {
        unchecked {
            _item.bidEndDate += _extendPeriodInDays;
        }
    } else if (block.timestamp >= _item.bidEndDate) {
        unchecked {
            _item.bidEndDate = block.timestamp + _extendPeriodInDays;
        }
    }

    emit ExtendAuction(id, extendPeriodInDays);
}


    /**
     * @dev Function to close the auction for a market item.
     * @param id The id of the market item.
     */
    function closeBidding(uint256 id)
        external
        nonReentrant
        isPaused
    {
        MarketItem storage _item = marketItems[id];

        bool _valid = _validateLength(id) &&
            _validateOwner(msg.sender, _item.seller) &&
            _validateOpenForBids(_item.flags);

        if(_valid == false) {
            revert InvalidMarketItem(id);
        }
        
        _item.flags &= ~OPEN_FOR_BIDS_FLAG;

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
        MarketItem storage _item = marketItems[id];

        bool _valid = _validateLength(id) &&
            _validateSold(_item.flags) &&
            _validateClosed(_item.flags) &&
            _validateOpenForBids(_item.flags);

        if(_valid == false) {
            revert InvalidMarketItem(id);
        }

        _item.flags &= ~OPEN_FOR_BIDS_FLAG;
        _item.flags |= SOLD_FLAG;

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

        bool openForBids = (_item.flags & OPEN_FOR_BIDS_FLAG) != 0;
        bool closed = (_item.flags & CLOSED_FLAG) != 0;
        bool sold = (_item.flags & SOLD_FLAG) != 0;

        return(
            _item.nftId,
            _item.price,
            _item.bidEndDate,
            _item.seller,
            _item.collection,
            openForBids,
            closed,
            sold
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
     * @param _amount The amount in wei.
     * @param _receiver The receiver's address.
     */
    function _safeSendPayment(
        uint256 _amount,
        address _receiver
    )
    internal
    {
        (bool _sent, ) = _receiver.call{value: _amount}("");
        
        if(_sent == false) {
            revert NotEnoughFunds(_amount);
        }
    }

    /**
     * @dev Function to check if a collection supports the ERC2981 interface.
     * @param _contract The address of the collection.
     */
    function _checkRoyalties(address _contract) internal view returns (bool) {
        (bool success) = IERC165(_contract).supportsInterface(_INTERFACE_ID_ERC2981);
        return success;
    }

    /**
     * @dev Function to validate the owner of a market item.
     * @param _caller The caller of the function.
     * @param _owner The owner of the market item.
     */
    function _validateOwner(address _caller, address _owner) internal pure returns(bool) {
        return _caller == _owner;
    }

    /**
     * @dev Function to validate the length of the market items array.
     */
    function _validateLength(uint256 _length) internal view returns(bool) {
        require(
            _length < marketItems.length,
            "Marketplace::Length must be greater than zero!"
        );

        return true;
    }

    /**
     * @dev Function to validate the sold flag.
     */
    function _validateSold(uint8 _flags) internal pure returns(bool) {
        if((_flags & SOLD_FLAG) == 0) {
            return true;
        }

        return false;
    }

    /**
     * @dev Function to validate the closed flag.
     */
    function _validateClosed(uint8 _flags) internal pure returns(bool) {
        if((_flags & CLOSED_FLAG) == 0) {
            return true;
        }

        return false;
    }

    /**
     * @dev Function to validate the openForBids flag.
     */
    function _validateOpenForBids(uint8 _flags) internal pure returns(bool) {
        if((_flags & OPEN_FOR_BIDS_FLAG) != 0) {
            return true;
        }

        return false;
    }

    /**
     * @dev Function to validate an address.
     */
    function _validateAddress(address _addr) internal pure returns(bool) {
        bool _valid = _addr != address(0) &&
            _addr != address(0xdead);

        return _valid;
    }
}
