// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/IFactory.sol";
import "../interfaces/ITangibleMarketplace.sol";
import "../abstract/AdminAccess.sol";
import "../interfaces/IInitialReSeller.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMarketplace {
    struct MarketItem {
        uint256 tokenId;
        address seller;
        address owner;
        address paymentToken;
        uint256 price;
        bool listed;
    }

    function _idToMarketItem(uint256 tokenId)
        external
        view
        returns (MarketItem memory);
}

interface ITnftFtnftMarketplace is ITangibleMarketplace {
    function marketplace(address tnft, uint256 tokenId)
        external
        view
        returns (Lot memory);

    function marketplaceFract(address ftnft, uint256 fractionId)
        external
        view
        returns (LotFract memory);
}

interface PINFTExt is PassiveIncomeNFT {
    function claimableIncomes(uint256[] calldata tokenIds)
        external
        view
        returns (uint256[] memory free, uint256[] memory max);

    function marketplace() external view returns (IMarketplace);
}

interface RevenueShareExt is RevenueShare {
    function total() external view returns (uint256);
}

interface IFactoryExt is IFactory {
    function fractionToTnftAndId(ITangibleFractionsNFT fraction)
        external
        view
        returns (TnftWithId memory);
}

interface ITangibleFractionsNFTExt is ITangibleFractionsNFT {
    function claimableIncome(uint256 fractionId)
        external
        view
        returns (uint256);
}

interface IInitialReSellerExt is IInitialReSeller {
    function saleData(ITangibleFractionsNFT ftnft)
        external
        view
        returns (FractionSaleData memory);
}

contract TangibleReaderHelper is AdminAccess {
    IFactoryExt public factory;

    constructor(IFactory _factory) {
        require(address(_factory) != address(0), "ZA");
        factory = IFactoryExt(address(_factory));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getLocksBatch(uint256[] calldata tokenIds)
        external
        view
        returns (PINFTExt.Lock[] memory locksBatch)
    {
        uint256 length = tokenIds.length;
        locksBatch = new PINFTExt.Lock[](length);

        for (uint256 i = 0; i < length; i++) {
            locksBatch[i] = factory.passiveNft().locks(tokenIds[i]);
        }
    }

    function getSharesBatch(uint256[] calldata tokenIds, address fromAddress)
        external
        view
        returns (int256[] memory sharesBatch, uint256 totalShare)
    {
        uint256 length = tokenIds.length;
        sharesBatch = new int256[](length);
        RevenueShareExt revenueShare = RevenueShareExt(
            address(factory.revenueShare())
        );

        totalShare = revenueShare.total();

        for (uint256 i = 0; i < length; i++) {
            sharesBatch[i] = revenueShare.share(
                abi.encodePacked(fromAddress, tokenIds[i])
            );
        }
    }

    function getPiNFTMarketItemBatch(uint256[] calldata tokenIds)
        external
        view
        returns (IMarketplace.MarketItem[] memory marketItems)
    {
        uint256 length = tokenIds.length;
        marketItems = new IMarketplace.MarketItem[](length);
        PINFTExt piNft = PINFTExt(address(factory.passiveNft()));
        IMarketplace piMarketplace = piNft.marketplace();

        for (uint256 i = 0; i < length; i++) {
            marketItems[i] = piMarketplace._idToMarketItem(tokenIds[i]);
        }
    }

    function ownersOBatch(uint256[] calldata tokenIds, address contractAddress)
        external
        view
        returns (address[] memory owners)
    {
        uint256 length = tokenIds.length;
        owners = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            owners[i] = IERC721(contractAddress).ownerOf(tokenIds[i]);
        }
    }

    function fractionToTnftAndIdBatch(
        ITangibleFractionsNFT[] calldata fractions
    ) external view returns (IFactoryExt.TnftWithId[] memory info) {
        uint256 length = fractions.length;
        info = new IFactoryExt.TnftWithId[](length);
        for (uint256 i = 0; i < length; i++) {
            info[i] = factory.fractionToTnftAndId(fractions[i]);
        }
    }

    function tokensFingerprintBatch(
        uint256[] calldata tokenIds,
        ITangibleNFT tnft
    ) external view returns (uint256[] memory passiveNfts) {
        uint256 length = tokenIds.length;
        passiveNfts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            passiveNfts[i] = tnft.tokensFingerprint(tokenIds[i]);
        }
    }

    function tnftsStorageEndTime(uint256[] calldata tokenIds, ITangibleNFT tnft)
        external
        view
        returns (uint256[] memory endTimes)
    {
        uint256 length = tokenIds.length;
        endTimes = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            endTimes[i] = tnft.storageEndTime(tokenIds[i]);
        }
    }

    function tokenByIndexBatch(
        uint256[] calldata indexes,
        address enumrableContract
    ) external view returns (uint256[] memory tokenIds) {
        uint256 length = indexes.length;
        tokenIds = new uint256[](length);
        for (uint256 i; i < length; i++) {
            tokenIds[i] = IERC721Enumerable(enumrableContract).tokenByIndex(
                indexes[i]
            );
        }
    }

    function claimableIncomeFractBatch(
        address ftnft,
        uint256[] calldata fractionIds
    ) public view returns (uint256[] memory claimables) {
        uint256 length = fractionIds.length;
        claimables = new uint256[](length);
        for (uint256 i; i < length; i++) {
            claimables[i] = ITangibleFractionsNFTExt(ftnft).claimableIncome(
                fractionIds[i]
            );
        }
    }

    function lotBatch(address nft, uint256[] calldata tokenIds)
        external
        view
        returns (ITnftFtnftMarketplace.Lot[] memory)
    {
        uint256 length = tokenIds.length;
        ITnftFtnftMarketplace.Lot[]
            memory result = new ITnftFtnftMarketplace.Lot[](length);
        ITnftFtnftMarketplace marketplace = ITnftFtnftMarketplace(
            factory.marketplace()
        );

        for (uint256 i = 0; i < length; i++) {
            result[i] = marketplace.marketplace(nft, tokenIds[i]);
        }

        return result;
    }

    function lotFractionBatch(address ftnft, uint256[] calldata tokenIds)
        external
        view
        returns (ITnftFtnftMarketplace.LotFract[] memory)
    {
        uint256 length = tokenIds.length;
        ITnftFtnftMarketplace.LotFract[]
            memory result = new ITnftFtnftMarketplace.LotFract[](length);
        ITnftFtnftMarketplace marketplace = ITnftFtnftMarketplace(
            factory.marketplace()
        );

        for (uint256 i = 0; i < length; i++) {
            result[i] = marketplace.marketplaceFract(ftnft, tokenIds[i]);
        }

        return result;
    }

    function saleDataBatch(ITangibleFractionsNFT[] calldata ftnfts)
        external
        view
        returns (IInitialReSeller.FractionSaleData[] memory result)
    {
        uint256 length = ftnfts.length;
        result = new IInitialReSeller.FractionSaleData[](length);
        for (uint256 i; i < length; i++) {
            result[i] = IInitialReSellerExt(factory.initReSeller()).saleData(
                ftnfts[i]
            );
        }
    }

    function fractionSharesBatch(
        ITangibleFractionsNFT ftnft,
        uint256[] calldata tokenIds
    ) external view returns (uint256[] memory shares) {
        uint256 length = tokenIds.length;
        shares = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            shares[i] = ftnft.fractionShares(tokenIds[i]);
        }
    }

}
