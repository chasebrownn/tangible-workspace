// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./interfaces/ITangibleNFT.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IOwnable.sol";
import "./abstract/AdminAccess.sol";

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TangibleNFT is AdminAccess, ERC1155, Pausable, ITangibleNFT {
    using Strings for uint256;

    // ~ State Variabls ~

    string public category;
    string public symbol;
    string public baseUri;


    /// @notice Initialize contract
    constructor(
        address _factory,
        string memory _category,
        string memory _symbol,
        string memory _uri
    ) ERC1155(_uri) {

        factory = _factory;
        category = _category;
        symbol = _symbol;
        baseUri = uri;
        
    }


    // ~ Modifiers ~

    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }

    // ~ External Functions ~


    // ~ Internal Functions ~


    // ~ Admin Functions ~

    /// @notice This function is used to update the baseUri state variable.
    /// @dev Only callable by factory admin.
    function setBaseURI(string _uri) external onlyFactoryAdmin {
        baseUri = _uri;
    }

    /// @notice This function is used to update the factory state variable.
    /// @dev Only callable by factory admin.
    function setFactory(address _factory) external onlyFactoryAdmin {
        factory = _factory;
    }

    /// @notice This function is used to update the paused state of this contract.
    /// @dev Only callable by factory admin.
    function togglePause() external onlyFactoryAdmin {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }


    // ~ View Functions ~

    /// @notice This function is used to return the baseUri string.
    function baseURI() external view returns (string memory) {
        return baseUri;
    }

    /// @notice This function is used to return the baseUri string with appended tokenId.
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseUri, "/", tokenId.toString()));
    }

}