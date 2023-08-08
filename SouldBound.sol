// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title Soulbound Token
 * @notice Token that can be emitted or revoked by a central entity
 *         DO NOT USE THIS SMART CONTRACT IN PRODUCTION!
 * @author Socarde Paul
 */

contract SoulBoundNft is ERC721 {

  /// Variables
  uint256 public counter;
  uint256 public upperLimit = 100;

  /// Enums
  enum Status {ACTIVE, REVOKED}
  enum Roles {OWNER, EMITTER, REVOKER}
  enum Type {PARTICIPATION, COMPLETION, FIRST_PLACE, SECOND_PLACE, THIRD_PLACE}

  /// Mappings
  mapping(address => Roles) public role;
  mapping(uint256 => Status) public status;
  mapping(uint256 => Type) public types;

  /// URIs
  string public REVOKED_URI;
  mapping(Type => string) public typeToURI;

  /// Errors
  error CantMint();
  error NotAuthorized();
  error AlreadyRevoked();
  error InvalidArguments();
  error CantTransferToken();

  /// Events
  event EmittedCertificate(address who, uint256 id);
  event RevokeCertificate(address owner, uint256 id);

  constructor() ERC721("SoulBoundNft", "SBN") {
    role[msg.sender] = Roles.OWNER;
  }

  /// Modifiers
  modifier onlyOwner {
    if(role[msg.sender] != Roles.OWNER) revert NotAuthorized();
    _;
  }

  modifier onlyEmitter {
    if(role[msg.sender] != Roles.EMITTER || role[msg.sender] != Roles.OWNER) revert NotAuthorized();
    _;
  }

  modifier onlyRevoker {
    if(role[msg.sender] != Roles.REVOKER || role[msg.sender] != Roles.OWNER) revert NotAuthorized();
    _;
  }

  /// @dev Function to emit a certificate
  function emitToken(address to, Type _type) external onlyEmitter {
    if(counter + 1 > upperLimit) revert CantMint();

    uint256 _counter = counter;
    counter++;

    _mint(to, _counter);
    _setStatus(_counter, true);
    _setType(_counter, _type);

    emit EmittedCertificate(to, _counter);
  }

  /// @dev Function to revoke a certificate
  /// @notice We do not burn the token. We mark it as "REVOKED" and display a different URI.
  ///         By doing this, 3rd party apps can see the certification was revokend and can
  ///         ask the emitter for the reason
  function revokeTokens(uint256 id) external onlyRevoker {
    if(status[id] == Status.REVOKED) revert AlreadyRevoked();
    _setStatus(id, false);

    emit RevokeCertificate(ownerOf(id), id);
  }

  /// @dev Internal function to set the status of a certificate
  function _setStatus(uint256 id, bool statusOfCertificate) internal {
    if(statusOfCertificate == true) {
      status[id] = Status.ACTIVE;
    } else {
      status[id] = Status.REVOKED;
    }
  }

  /// @dev Internal function to set the type of certification
  function _setType(uint256 id, Type _type) internal {
    types[id] = _type;
  }

  /// @dev Override the transfer function
  function _transfer(address from, address to, uint256 tokenId) internal virtual override {
    if(from != address(0) || to != address(0)) revert CantTransferToken();
    super._transfer(from, to, tokenId);
  }

  /// @dev Display the URI depending on the status of certificate
  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    _requireMinted(tokenId);

    string memory finalURI;

    if(status[tokenId] == Status.REVOKED) {
        finalURI = REVOKED_URI;
    } else {
        finalURI = typeToURI[types[tokenId]];
    }
    return finalURI;
  }

  /// @dev Function to set the URI
  function setURIForTypes(string[] calldata _uris, Type[] calldata _types) external onlyOwner {
    if(_uris.length != uint256(type(Type).max) + 1 && _uris.length != _types.length) revert InvalidArguments();

    for(uint256 i = 0; i <= _uris.length; i++) {
        typeToURI[_types[i]] = _uris[i];
    }
  }

  /// @dev Function to set the REVOKED URI
  function setURIForRevoked(string calldata _uri) external onlyOwner {
    REVOKED_URI = _uri;
  }

  /// @dev Function to add roles in the smart contract
  function addRoles(address[] calldata who, Roles[] memory givenRoles) external onlyOwner {
    if(who.length != givenRoles.length) revert InvalidArguments();

    for(uint256 i=0; i<= who.length; i++) {
        role[who[i]] = givenRoles[i];
    }
  }

  /// @dev Function to revoke roles in the smart contract
  function revokeRoles(address[] calldata who) external onlyOwner {
    for(uint256 i=0; i<= who.length; i++) {
            delete role[who[i]];
    }
  }
}