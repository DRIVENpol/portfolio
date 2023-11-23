// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @author Rev3al LLC.
 * @title Simple ERC-721 Smart Contract.
 */

/** IMPORTS */
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Single_Nft is ERC721, ERC721URIStorage, Ownable, ERC2981 {

    /**
     * @dev Constructor.
     * @param _fee - Royalty fee.
     * @param _owner - Owner of the NFT.
     * @param _name - Name of the NFT.
     * @param _symbol - Symbol of the NFT.
     * @param _uri - URI of the NFT.
     */
    constructor(
        uint96 _fee,
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) ERC721(_name, _symbol) {

        _mintWithRoyalties(_owner, _uri, _fee);
    }

    /**
     * @dev Internal function to mint a new NFT with a tokenURI and royalty fee.
     * @param _recipient - Address of the recipient.
     * @param _uri - URI of the NFT.
     * @param _fee - Royalty fee.
     */
    function _mintWithRoyalties(
        address _recipient, 
        string memory _uri, 
        uint96 _fee
    ) 
    internal
    {
            _mint(_recipient, 0);
            _setTokenURI(0, _uri);
            _setTokenRoyalty(0, _recipient, _fee);
    }

    /**
     *@dev Internal function to burn a specific NFT.
     */
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    /**
     * @dev Internal function to set the tokenURI for a specific NFT.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
