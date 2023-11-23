// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @author Rev3al LLC.
 * @title Simple ERC-721 Smart Contract.
 */

/** IMPORTS */
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

contract ERC721_Collection is ERC721, Ownable, ERC2981 {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    string public uriPrefix = "";
    string public uriSuffix = ".json";
    string public hiddenMetadataUri;
    
    uint256 public cost;
    uint256 public maxSupply;
    uint256 public maxMintAmountPerTx;
    uint96 public royalties;

    bool public paused = true;
    bool public revealed = false;

    constructor(
        uint256 _cost,
        uint256 _maxSupply,
        uint256 _maxMintAmountPerTx,
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _uriPrefix,
        string memory _hiddenURI,
        bool _reveal
    ) ERC721(_name, _symbol) {
        require(
            _maxSupply > 0,
            "Invalid supply!"
        );

        cost = _cost;
        maxSupply = _maxSupply;
        maxMintAmountPerTx = _maxMintAmountPerTx;
        uriPrefix = _uriPrefix;

        transferOwnership(_owner);

        if(!_reveal) {
            setHiddenMetadataUri(_hiddenURI); //"ipfs://__CID__/hidden.json"
        } else {
            revealed = true;
        }
    }

    modifier mintCompliance(uint256 _mintAmount) {
        if(maxMintAmountPerTx == 0) {
            require(
                _mintAmount > 0, 
                "Invalid mint amount!"
            );
        } else if(maxMintAmountPerTx > 0) {
            require(
                _mintAmount > 0 && 
                _mintAmount <= maxMintAmountPerTx, 
                "Invalid mint amount!"
            );
        }

        require(
            supply.current() + _mintAmount <= maxSupply, 
            "Max supply exceeded!"
        );
        _;
    }

    /** EXTERNAL FUNCTIONS */
    function mint(
        uint256 _mintAmount
    ) 
    external 
    payable 
    mintCompliance(_mintAmount) 
    {
        require(
            !paused, 
            "The contract is paused!"
        );
        require(
            msg.value >= cost * _mintAmount, 
            "Insufficient funds!"
        );

        _mintLoop(msg.sender, _mintAmount);
    }
    
    function mintForAddress(
        uint256 _mintAmount, 
        address _receiver
    ) 
    external
    onlyOwner
    mintCompliance(_mintAmount) 
    {
        _mintLoop(_receiver, _mintAmount);
    }

    function setUriPrefix(
        string memory _uriPrefix
    ) 
    external
    onlyOwner 
    {
        uriPrefix = _uriPrefix;
    }

    function setUriSuffix(
        string memory _uriSuffix
    ) 
    external 
    onlyOwner {
        uriSuffix = _uriSuffix;
    }

    function setPaused(
        bool _state
    ) 
    external 
    onlyOwner 
    {
        require(
            paused != _state,
            "State already in use!"
        );
        paused = _state;
    }

    function withdraw() 
        external 
        onlyOwner 
    {
        (bool _success, ) = payable(owner()).call{value: address(this).balance}("");
        require(_success);
    }

    function setRevealed(
        bool _state
    ) 
    external 
    onlyOwner 
    {
        require(
            revealed != _state,
            "State used!"
        );
        revealed = _state;
    }

    function setCost(
        uint256 _cost
    ) 
    external 
    onlyOwner {
        cost = _cost;
    }

    function setRoyalty(
        uint96 _royalties
    )   
    external
    onlyOwner
    {
        royalties = _royalties;
    }

    function setMaxMintAmountPerTx(
        uint256 _maxMintAmountPerTx
    ) 
    external 
    onlyOwner 
    {
        maxMintAmountPerTx = _maxMintAmountPerTx;
    }

    /** PUBLIC FUNCTIONS */
    function setHiddenMetadataUri(
        string memory _hiddenMetadataUri
    ) 
    public 
    onlyOwner 
    {
        hiddenMetadataUri = _hiddenMetadataUri;
    }

    function totalSupply() public view returns (uint256) {
        return supply.current();
    }

    /** EXTERNAL VIEW */
    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = 1;
        uint256 ownedTokenIndex = 0;

        while (ownedTokenIndex < ownerTokenCount && currentTokenId <= maxSupply) {
        address currentTokenOwner = ownerOf(currentTokenId);

        if (currentTokenOwner == _owner) {
            ownedTokenIds[ownedTokenIndex] = currentTokenId;

            ownedTokenIndex++;
        }

        currentTokenId++;
        }

        return ownedTokenIds;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
        _exists(_tokenId),
        "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed == false) {
        return hiddenMetadataUri;
        }

        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0
            ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
            : "";
    }

    /** INTERNAL FUNCTIONS */
    function _mintLoop(
        address _receiver, 
        uint256 _mintAmount
    ) 
    internal 
    {
        for (uint256 i = 0; i < _mintAmount;) {
            supply.increment();
            _mint(_receiver, supply.current());
            _setTokenRoyalty(supply.current(), _receiver, royalties);

            unchecked {
                ++i;
            }
        }
  }

    function _baseURI() 
        internal 
        view 
        virtual 
        override 
        returns (string memory) 
    {
        return uriPrefix;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}