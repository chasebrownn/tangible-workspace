// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./ITangibleNFT.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/// @title ITangibleNFT interface defines the interface of the TangibleNFT
interface ITangibleFractionsNFT is IERC721, IERC721Metadata, IERC721Enumerable {
    event ProducedInitialFTNFTs(uint256 keepToken, uint256 sellToken);
    event ProducedFTNFTs(uint256[] fractionsIds);

    function tnft() external view returns (ITangibleNFT nft);

    function tnftTokenId() external view returns (uint256 tokenId);

    function tnftFingerprint() external view returns (uint256 fingerprint);

    function fullShare() external view returns (uint256 fullShare);

    function fractionShares(uint256 tokenId)
        external
        view
        returns (uint256 share);

    function initialSplit(
        address owner,
        address _tnft,
        uint256 _tnftTokenId,
        uint256 keepShare,
        uint256 sellShare
    ) external returns (uint256 tokenKeep, uint256 tokenSell);

    function fractionalize(uint256 fractionTokenId, uint256[] calldata shares)
        external
        returns (uint256[] memory splitedShares);

    function defractionalize(uint256[] memory tokenIds) external;

    function claimFor(address contractAddress, uint256 tokenId) external;
}
