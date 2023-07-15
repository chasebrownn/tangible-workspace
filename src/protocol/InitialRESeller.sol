// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/IInitialReSeller.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/ITangibleMarketplace.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IFactoryExt is IFactory {
    function fractionToTnftAndId(ITangibleFractionsNFT fraction)
        external
        view
        returns (TnftWithId memory);

    function takeFtnftForReemburse(
        ITangibleFractionsNFT ftnft,
        uint256 fractionId
    ) external;

    function paymentTokens(IERC20 token) external returns (bool);
}

interface IMarketplaceExt is ITangibleMarketplace {
    function stopFractSale(ITangibleFractionsNFT ftnft, uint256 tokenId)
        external;

    function sellFraction(
        ITangibleFractionsNFT ftnft,
        uint256 fractTokenId,
        uint256[] calldata shares,
        uint256 price,
        uint256 minPurchaseShare
    ) external;
}

interface IInitialReSellerExt is IInitialReSeller {
    function soldTokens(ITangibleFractionsNFT ftnft)
        external
        view
        returns (uint256[] memory);

    function saleData(ITangibleFractionsNFT ftnft)
        external
        view
        returns (FractionSaleData memory);

    function getSoldTokens(ITangibleFractionsNFT ftnft)
        external
        view
        returns (uint256[] memory);

    function getSaleBuyersData(ITangibleFractionsNFT ftnft, uint256 tokenId)
        external
        view
        returns (FractionBuyer memory);
}

contract InitialReSeller is IInitialReSeller, IERC721Receiver {
    using SafeERC20 for IERC20;

    IFactoryExt factory;
    //handle multiple sales
    mapping(ITangibleFractionsNFT => FractionSaleData) public saleData;
    //data used for reembursing if sale fails
    // ftnft and fractionId identify buyer
    mapping(ITangibleFractionsNFT => mapping(uint256 => FractionBuyer))
        public saleBuyersData;

    mapping(ITangibleFractionsNFT => uint256[]) public soldTokens;

    address[] public currentlySellingRe;
    address[] public soldRe;

    modifier onlyFactoryAdmin() {
        require(factory.isFactoryAdmin(msg.sender), "NFA");
        _;
    }

    modifier onlyMarketplace() {
        require(address(factory.marketplace()) == msg.sender, "NMAR");
        _;
    }

    modifier onlyFactory() {
        require(address(factory) == msg.sender, "NFAC");
        _;
    }

    constructor(address _factory) {
        require(_factory != address(0), "ZA");
        factory = IFactoryExt(_factory);
    }

    function getSoldRealEstate() external view returns (address[] memory) {
        return soldRe;
    }

    function getSoldRealEstateSize() external view returns (uint256) {
        return soldRe.length;
    }

    function getSoldTokens(ITangibleFractionsNFT ftnft)
        external
        view
        returns (uint256[] memory)
    {
        return soldTokens[ftnft];
    }

    function getSoldTokensSize(ITangibleFractionsNFT ftnft)
        external
        view
        returns (uint256)
    {
        return soldTokens[ftnft].length;
    }

    function getSaleBuyersData(ITangibleFractionsNFT ftnft, uint256 tokenId)
        external
        view
        returns (FractionBuyer memory)
    {
        return saleBuyersData[ftnft][tokenId];
    }

    function getCurrentlySellingRealEstate()
        external
        view
        returns (address[] memory)
    {
        return currentlySellingRe;
    }

    function getCurrentlySellingRealEstateSize()
        external
        view
        returns (uint256)
    {
        return currentlySellingRe.length;
    }

    function withdrawFtnft(
        ITangibleFractionsNFT ftnft,
        uint256[] calldata tokenIds
    ) external onlyFactoryAdmin {
        //defract tokens and send them as 1
        ftnft.defractionalize(tokenIds);
        uint256 totalSupply = ftnft.totalSupply();
        if (totalSupply > 0) {
            ftnft.safeTransferFrom(address(this), msg.sender, tokenIds[0]);
        } else {
            //defract whole, send token back to admin
            ITangibleNFT tnft = ftnft.tnft();
            uint256 tnftTokenId = ftnft.tnftTokenId();
            tnft.safeTransferFrom(address(this), msg.sender, tnftTokenId);
        }
    }

    function updateBuyer(
        ITangibleFractionsNFT ftnft,
        address buyer,
        uint256 fractionId,
        uint256 amountPaid
    ) external override onlyMarketplace {
        //set fraction sale data to update
        soldTokens[ftnft].push(fractionId);
        FractionBuyer memory fb = FractionBuyer(
            buyer,
            fractionId,
            ftnft.fractionShares(fractionId),
            amountPaid,
            soldTokens[ftnft].length - 1
        );
        //store in db
        saleBuyersData[ftnft][fractionId] = fb;
        //update total
        saleData[ftnft].paidSoFar += amountPaid;
        emit StoreBuyer(ftnft, fractionId, buyer, amountPaid);
    }

    function canSellFractions(ITangibleFractionsNFT ftnft)
        external
        view
        override
        returns (bool)
    {
        if (
            (saleData[ftnft].endTimestamp >= block.timestamp) &&
            saleData[ftnft].startTimestamp <= block.timestamp
        ) {
            return true;
        }
        return false;
    }

    function completeSale(ITangibleFractionsNFT ftnft)
        external
        override
        onlyFactory
    {
        uint256 balance = saleData[ftnft].askingPrice ==
            saleData[ftnft].paidSoFar
            ? saleData[ftnft].askingPrice
            : saleData[ftnft].paidSoFar;

        saleData[ftnft].paymentToken.safeTransfer(
            factory.feeStorageAddress(),
            balance
        );
        saleData[ftnft].sold = true;
        //end time now because sale completed
        saleData[ftnft].endTimestamp = block.timestamp;
        _removeCurrentlySelling(saleData[ftnft].indexInCurrentlySelling);
        //store sold RE
        soldRe.push(address(ftnft));
        saleData[ftnft].indexInCurrentlySelling = type(uint256).max;
        saleData[ftnft].indexInSold = soldRe.length - 1;
        //we don't remove saleData because it is permanent record of sale

        emit SaleAmountTaken(ftnft, saleData[ftnft].paymentToken, balance);
    }

    function extendSaleEndDate(ITangibleFractionsNFT ftnft, uint256 endDate)
        external
        onlyFactoryAdmin
    {
        require(saleData[ftnft].startTimestamp < endDate, "date1");
        //set new end date
        saleData[ftnft].endTimestamp = endDate;
        emit EndDateExtended(ftnft, endDate);
    }

    function extendSaleStartDate(ITangibleFractionsNFT ftnft, uint256 startDate)
        external
        onlyFactoryAdmin
    {
        require(saleData[ftnft].endTimestamp > startDate, "date2");
        //set new start date
        saleData[ftnft].startTimestamp = startDate;
        emit StartDateExtended(ftnft, startDate);
    }

    function putOnSale(
        ITangibleNFT tnft,
        IERC20 paymentToken,
        uint256 tokenId,
        uint256 askingPrice,
        uint256 minPurchaseShare,
        uint256 endSaleDate,
        uint256 startSaleDate
    ) external onlyFactoryAdmin {
        require(tnft.paysRent(), "Only RE");
        require(factory.paymentTokens(paymentToken), "only approved tokens");
        require((endSaleDate >= startSaleDate), "Sale date wrong");
        if (startSaleDate > 0) {
            require((startSaleDate >= block.timestamp), "Start");
        }
        ITangibleFractionsNFT ftnft = factory.fractions(tnft, tokenId);
        if (address(ftnft) != address(0)) {
            require(
                !factory.fractionToTnftAndId(ftnft).initialSaleDone,
                "sale already done"
            );
        }
        //check if payment token is approved
        ITangibleMarketplace marketplace = ITangibleMarketplace(
            factory.marketplace()
        );
        //take tnft
        tnft.safeTransferFrom(msg.sender, address(this), tokenId);
        //approve marketplace
        tnft.approve(address(marketplace), tokenId);
        //sell the fractions from whole nft
        uint256 tokenToSell;
        (ftnft, tokenToSell) = marketplace.sellFractionInitial(
            tnft,
            paymentToken,
            tokenId,
            0,
            10000000,
            askingPrice,
            minPurchaseShare
        );
        uint256 startTimestamp = startSaleDate == 0
            ? block.timestamp
            : startSaleDate;
        uint256 endTimestamp = endSaleDate == 0
            ? (block.timestamp + (2 * 7 days))
            : endSaleDate;

        //update currently selling array and store it in fsd
        currentlySellingRe.push(address(ftnft));
        FractionSaleData memory fsd = FractionSaleData(
            paymentToken,
            tokenToSell,
            endTimestamp,
            startTimestamp,
            askingPrice,
            0,
            (currentlySellingRe.length - 1),
            type(uint256).max, //index in already sold - default to be max means doesn't exist
            false
        );
        saleData[ftnft] = fsd;

        emit SaleStarted(
            ftnft,
            startTimestamp,
            endTimestamp,
            tokenToSell,
            askingPrice
        );
    }

    function modifySale(
        ITangibleFractionsNFT ftnft,
        uint256 fractionId,
        uint256 askingPrice,
        uint256 minPurchaseShare
    ) external onlyFactoryAdmin {
        IMarketplaceExt marketplace = IMarketplaceExt(factory.marketplace());
        uint256[] memory shares = new uint256[](2);
        marketplace.sellFraction(
            ftnft,
            fractionId,
            shares,
            askingPrice,
            minPurchaseShare
        );
    }

    function reemburse(ITangibleFractionsNFT ftnft, uint256[] calldata tokenIds)
        external
        onlyFactoryAdmin
    {
        //reeburse only if end date expired
        require(!saleData[ftnft].sold, "RE sold");
        require(
            saleData[ftnft].endTimestamp < block.timestamp,
            "Sale not expired"
        );
        uint256 length = tokenIds.length;
        for (uint256 i; i < length; i++) {
            //take ftnft from buyer
            address owner = saleBuyersData[ftnft][tokenIds[i]].owner;
            require(owner != address(0), "taken");

            factory.takeFtnftForReemburse(ftnft, tokenIds[i]);
            //send back the money
            saleData[ftnft].paymentToken.safeTransfer(
                owner,
                saleBuyersData[ftnft][tokenIds[i]].pricePaid
            );
            //delete records
            _removeSoldToken(
                ftnft,
                saleBuyersData[ftnft][tokenIds[i]].indexInSoldTokens
            );
            delete saleBuyersData[ftnft][tokenIds[i]];
        }
    }

    //call this when everyone is reembuursed
    function stopSale(ITangibleFractionsNFT ftnft) external onlyFactoryAdmin {
        require(soldTokens[ftnft].length == 0, "Reemburse not done");
        IMarketplaceExt marketplace = IMarketplaceExt(factory.marketplace());
        marketplace.stopFractSale(ftnft, saleData[ftnft].sellingToken);

        //update indexes in saleData and remove from currentlySelling
        _removeCurrentlySelling(saleData[ftnft].indexInCurrentlySelling);
        delete saleData[ftnft];
    }

    //this function is not preserving order, and we don't care about it
    function _removeCurrentlySelling(uint256 index) internal {
        require(index < currentlySellingRe.length);
        //take last ftnft
        ITangibleFractionsNFT ftnft = ITangibleFractionsNFT(
            currentlySellingRe[currentlySellingRe.length - 1]
        );
        //replace it with the one we are removing
        currentlySellingRe[index] = address(ftnft);
        //set it's new index in saleData
        saleData[ftnft].indexInCurrentlySelling = index;
        currentlySellingRe.pop();
    }

    function _removeSoldToken(ITangibleFractionsNFT ftnft, uint256 index)
        internal
    {
        require(index < soldTokens[ftnft].length);
        //take last ftnft
        uint256 tokenId = soldTokens[ftnft][soldTokens[ftnft].length - 1];

        //replace it with the one we are removing
        soldTokens[ftnft][index] = tokenId;
        //set it's new index in saleData
        saleBuyersData[ftnft][tokenId].indexInSoldTokens = index;
        soldTokens[ftnft].pop();
    }

    function migrateSoldRe(address[] calldata _soldRe)
        external
        onlyFactoryAdmin
    {
        soldRe = _soldRe;
    }

    function migrateSoldTokens(
        IInitialReSellerExt oldReseller,
        ITangibleFractionsNFT[] calldata tokens
    ) external onlyFactoryAdmin {
        uint256 length = tokens.length;
        for (uint256 i; i < length; i++) {
            uint256[] memory soldT = oldReseller.getSoldTokens(tokens[i]);
            uint256 lengthS = soldT.length;
            for (uint256 j; i < lengthS; j++) {
                soldTokens[tokens[i]][j] = soldT[j];
            }
        }
    }

    function migrateSaleBuyersData(
        IInitialReSellerExt oldReseller,
        ITangibleFractionsNFT ftnft,
        uint256[] calldata tokenIds
    ) external onlyFactoryAdmin {
        uint256 length = tokenIds.length;
        for (uint256 i; i < length; i++) {
            saleBuyersData[ftnft][tokenIds[i]] = oldReseller.getSaleBuyersData(ftnft, tokenIds[i]);
            
        }
    }

    function migrateSaleData(
        IInitialReSellerExt oldReseller,
        ITangibleFractionsNFT[] calldata tokens
    ) external onlyFactoryAdmin {
        uint256 length = tokens.length;
        for (uint256 i; i < length; i++) {
            saleData[tokens[i]] = oldReseller.saleData(tokens[i]);
        }
    }

    function withdrawToken(address token, uint256 amount)
        external
        onlyFactoryAdmin
    {
        IERC20(token).safeTransfer(
            msg.sender,
            amount == 0 ? IERC20(token).balanceOf(address(this)) : amount
        );
    }

    function onERC721Received(
        address, /*operator*/
        address, /*seller*/
        uint256, /*tokenId*/
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
