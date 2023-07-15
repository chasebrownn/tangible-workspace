// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IFactory.sol";

/// @title ITangibleMarketplace interface defines the interface of the Marketplace
interface ITangibleMarketplace is IVoucher {
    struct Lot {
        ITangibleNFT nft;
        IERC20 paymentToken;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool minted;
    }

    struct LotFract {
        ITangibleFractionsNFT nft;
        IERC20 paymentToken;
        uint256 tokenId;
        address seller;
        uint256 price; //total wanted price for share
        uint256 minShare;
        uint256 initialShare;
    }

    event MarketplaceFeePaid(
        address indexed nft,
        uint256 indexed tokenId,
        uint256 feeAmount
    );

    event Selling(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 price
    );
    event StopSelling(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId
    );
    event Sold(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 price
    );
    event Bought(
        address indexed buyer,
        address indexed nft,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );

    event SellingFract(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 price
    );
    event StopSellingFract(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId
    );
    event SoldFract(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 price
    );
    event BoughtFract(
        address indexed buyer,
        address indexed nft,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );

    event SellFeeAddressSet(address indexed oldFee, address indexed newFee);
    event SellFeeChanged(
        ITangibleNFT indexed nft,
        uint256 oldFee,
        uint256 newFee
    );
    event SetFactory(address indexed oldFactory, address indexed newFactory);
    event StorageFeePaid(
        address indexed payer,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 _years,
        uint256 amount
    );

    /// @dev The function allows anyone to put on sale the TangibleNFTs they own
    /// if price is 0 - use oracle when selling
    function sellBatch(
        ITangibleNFT nft,
        IERC20 paymentToken,
        uint256[] calldata tokenIds,
        uint256[] calldata price
    ) external;

    /// @dev The function allows the owner of the minted TangibleNFT items to remove them from the Marketplace
    function stopBatchSale(ITangibleNFT nft, uint256[] calldata tokenIds)
        external;

    /// @dev The function allows the user to buy any TangibleNFT from the Marketplace for USDC
    function buy(
        ITangibleNFT nft,
        uint256 tokenId,
        uint256 _years
    ) external;

    /// @dev The function allows the user to buy any TangibleNFT from the Marketplace for USDC this is for unminted items
    function buyUnminted(
        ITangibleNFT nft,
        uint256 _fingerprint,
        uint256 _years,
        bool _onlyLock
    ) external;

    /// @dev The function returns the address of the fee storage.
    function sellFeeAddress() external view returns (address);

    /// @dev The function which buys additional storage to token.
    function payStorage(
        ITangibleNFT nft,
        uint256 tokenId,
        uint256 _years
    ) external;

    function sellFractionInitial(
        ITangibleNFT tnft,
        IERC20 paymentToken,
        uint256 tokenId,
        uint256 keepShare,
        uint256 sellShare,
        uint256 sellSharePrice,
        uint256 minPurchaseShare
    ) external returns (ITangibleFractionsNFT ftnft, uint256 tokenToSell);
}
