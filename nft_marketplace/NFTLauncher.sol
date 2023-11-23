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

import "./SingleNft.sol";
import "./Collection.sol";

contract Rev3al_NftLauncher is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    
    /** ANALYTICS */
    uint256 public singleNftsLaunched;
    uint256 public collectionsLaunched;

    /** FEES */
    uint256 public singleNftFee;
    uint256 public collectionFee;

    /** MAPPING */
    mapping(address => address[]) public userToSingleNft;
    mapping(address => address[]) public userToCollection;

    /** EVENTS */
    event Nft_Created(address indexed nft);

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
    function createSingleNft(
        string memory name,
        string memory symbol,
        string memory uri
    ) 
    external 
    payable 
    {
        require(
            bytes(name).length > 0,
            "Invalid name!"
        );
        require(
            bytes(symbol).length > 0,
            "Invalid symbol!"
        );
        require(
            bytes(uri).length > 0,
            "Invalid uri!"
        );
        require(
            msg.value > singleNftFee,
            "Can't provide fee!"
        );

        Single_Nft sn = new Single_Nft(
            msg.sender,
            name,
            symbol,
            uri
        );

        userToSingleNft[msg.sender].push(address(sn));

        unchecked {
            ++singleNftsLaunched;
        }

        emit Nft_Created(address(sn));
    }

    function createCollection(
        uint256 maxSupply,
        uint256 cost,
        uint256 maxMintAmountPerTx,
        string memory name,
        string memory symbol,
        string memory uriPrefix,
        string memory hiddenUri,
        bool isPrivate
    )
    external
    payable
    {
        require(
            bytes(name).length > 0,
            "Invalid name!"
        );
        require(
            bytes(symbol).length > 0,
            "Invalid symbol!"
        );
        require(
            bytes(uriPrefix).length > 0,
            "Invalid uriPrefix!"
        );
        require(
            bytes(hiddenUri).length > 0,
            "Invalid hiddenUri!"
        );
        require(
            msg.value > collectionFee,
            "Can't provide fee!"
        );

        Collection c = new ERC721_Collection(
            maxSupply,
            cost,
            maxMintAmountPerTx,
            msg.sender,
            name,
            symbol,
            uriPrefix,
            hiddenUri,
            isPrivate
        );

        userToCollection[msg.sender].push(address(c));

        unchecked {
            ++collectionsLaunched;
        }

        emit Nft_Created(address(c));
    }

    receive() external payable {}

    /**
     * @dev Function to withdraw the native token from the contract.
     */
    function withdrawNative() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "Withdraw failed!");
    }
}