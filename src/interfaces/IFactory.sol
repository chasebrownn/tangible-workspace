// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./IVoucher.sol";
import "./ITangiblePriceManager.sol";
import "./ITangibleFractionsNFT.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface RevenueShare {
    function claimForToken(address contractAddress, uint256 tokenId) external;

    function share(bytes memory token) external view returns (int256);

    function updateShare(
        address contractAddress,
        uint256 tokenId,
        int256 amount
    ) external;

    function unregisterContract(address contractAddress) external;
}

interface RentShare {
    function forToken(address contractAddress, uint256 tokenId)
        external
        returns (RevenueShare);
}

interface PassiveIncomeNFT {
    struct Lock {
        uint256 startTime;
        uint256 endTime;
        uint256 lockedAmount;
        uint256 multiplier;
        uint256 claimed;
        uint256 maxPayout;
    }

    function locks(uint256 piTokenId) external view returns (Lock memory lock);

    function burn(uint256 tokenId) external returns (uint256 amount);

    function maxLockDuration() external view returns (uint8);

    function claim(uint256 tokenId, uint256 amount) external;

    function canEarnForAmount(uint256 tngblAmount) external view returns (bool);

    function claimableIncome(uint256 tokenId)
        external
        view
        returns (uint256, uint256);

    function mint(
        address minter,
        uint256 lockedAmount,
        uint8 lockDurationInMonths,
        bool onlyLock,
        bool generateRevenue
    ) external returns (uint256);

    function setGenerateRevenue(uint256 piTokenId, bool generate) external;
}

/// @title IFactory interface defines the interface of the Factory which creates NFTs.
interface IFactory is IVoucher {
    event MarketplaceAddressSet(
        address indexed oldAddress,
        address indexed newAddress
    );
    event InstantLiquidityAddressSet(
        address indexed oldAddress,
        address indexed newAddress
    );

    struct TnftWithId {
        ITangibleNFT tnft;
        uint256 tnftTokenId;
        bool initialSaleDone;
    }

    event WhitelistedBuyer(address indexed buyer, bool indexed approved);

    event MintedTokens(address indexed nft, uint256[] tokenIds);
    event PaymentToken(address indexed token, bool approved);
    event NewCategoryDeployed(address tnftCategory);
    event NewFractionDeployed(address fraction);
    event InitialFract(
        address indexed ftnft,
        uint256 indexed tokenKeep,
        uint256 indexed tokenSell
    );

    function decreaseInstantLiquidityStock(
        ITangibleNFT nft,
        uint256 fingerprint
    ) external;

    /// @dev The function which does lazy minting.
    function mint(MintVoucher calldata voucher)
        external
        returns (uint256[] memory);

    /// @dev The function that redeems tnft/sets status of tnft
    function redeemToggle(RedeemVoucher calldata voucher) external;

    /// @dev The function returns the address of the fee storage.
    function feeStorageAddress() external view returns (address);

    /// @dev The function returns the address of the marketplace.
    function marketplace() external view returns (address);

    /// @dev Returns dao owner
    function tangibleDao() external view returns (address);

    /// @dev The function returns the address of the tnft deployer.
    function deployer() external view returns (address);

    /// @dev The function returns the address of the priceManager.
    function priceManager() external view returns (ITangiblePriceManager);

    //complete initial sale of rent fractions
    function initialSaleFinished(ITangibleFractionsNFT ftnft) external;

    //contract for initial sale of fractions
    function initReSeller() external view returns (address);

    /// @dev The function returns the address of the USDC token.
    function USDC() external view returns (IERC20);

    /// @dev The function returns the address of the TNGBL token.
    function TNGBL() external view returns (IERC20);

    /// @dev The function creates new category and returns an address of newly created contract.
    function newCategory(
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        address priceOracle,
        uint256 _lockPercentage,
        bool _paysRent
    ) external returns (ITangibleNFT);

    function newFractionTnft(ITangibleNFT _tnft, uint256 _tnftTokenId)
        external
        returns (ITangibleFractionsNFT);

    function initialTnftSplit(MintInitialFractionVoucher calldata voucher)
        external
        returns (uint256 tokenKeep, uint256 tokenSell);

    /// @dev The function returns an address of category NFT.
    function category(string calldata name)
        external
        view
        returns (ITangibleNFT);

    function fractions(ITangibleNFT tnft, uint256 tnftTokenId)
        external
        view
        returns (ITangibleFractionsNFT);

    /// @dev The function returns if address is operator in Factory
    function isFactoryOperator(address operator) external view returns (bool);

    /// @dev The function returns if address is vendor in Factory
    function isFactoryAdmin(address admin) external view returns (bool);

    /// @dev The function pays for storage, called only by marketplace
    function adjustStorageAndGetAmount(
        ITangibleNFT tnft,
        uint256 tokenId,
        uint256 _years
    ) external returns (uint256);

    function payTnftStorageWithManager(
        ITangibleNFT tnft,
        uint256 tokenId,
        uint256 _years
    ) external;

    function lockTNGBLOnTNFT(
        ITangibleNFT tnft,
        uint256 tokenId,
        uint256 _years,
        uint256 lockedAmountTNGBL,
        bool onlyLock
    ) external;

    /// @dev updates oracle for already deployed tnft
    function updateOracleForTnft(string calldata name, address priceOracle)
        external;

    function defUSD() external returns (IERC20);

    /// @dev for migration puproses, we must avoid unnecessary deployments on new factories!
    function setCategory(
        string calldata name,
        ITangibleNFT nft,
        address priceOracle
    ) external;

    /// @dev fetches RevenueShareContract
    function revenueShare() external view returns (RevenueShare);

    /// @dev fetches RevenueShareContract
    function rentShare() external view returns (RentShare);

    /// @dev fetches PassiveIncomeNFTContract
    function passiveNft() external view returns (PassiveIncomeNFT);

    function onlyWhitelistedForUnmintedCategory(ITangibleNFT nft)
        external
        view
        returns (bool);

    function shouldLockTngbl(uint256 tngblAmount) external view returns (bool);

    function whitelistForBuyUnminted(address buyer)
        external
        view
        returns (bool);
}
