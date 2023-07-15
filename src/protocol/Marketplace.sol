// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/ITangibleMarketplace.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/ISellFeeDistributor.sol";
import "../interfaces/IOwnable.sol";
import "../interfaces/IInitialReSeller.sol";
import "../interfaces/IOnSaleTracker.sol";

import "../interfaces/IExchange.sol";
import "../abstract/AdminAccess.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IFactoryExt is IFactory {
    function fractionToTnftAndId(ITangibleFractionsNFT fraction)
        external
        view
        returns (TnftWithId memory);

    function paymentTokens(IERC20 token) external returns (bool);
}

interface IInitialReSellerExt is IInitialReSeller {
    function saleData(ITangibleFractionsNFT ftnft)
        external
        view
        returns (FractionSaleData memory);
}

contract Marketplace is AdminAccess, ITangibleMarketplace, IERC721Receiver {
    using SafeERC20 for IERC20;
    IFactoryExt public factory;

    struct PricesOracle {
        uint256 _weSellAt;
        uint256 _weSellAtStock;
        uint256 _weBuyAt;
        uint256 _weBuyAtStock;
        uint256 _lockedAmount;
    }

    struct PricesOracleArrays {
        uint256[] weSellAt;
        uint256[] weSellAtStock;
        uint256[] weBuyAt;
        uint256[] weBuyAtStock;
        uint256[] lockedAmount;
    }

    mapping(address => mapping(uint256 => Lot)) public marketplace;
    mapping(address => mapping(uint256 => LotFract)) public marketplaceFract;

    address public override sellFeeAddress;

    IExchange public exchange;
    IOnSaleTracker public onSaleTracker;

    // Default sell fee is 2.5% 250
    mapping(ITangibleNFT => uint256) public feesPerCategory;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc ITangibleMarketplace
    function sellBatch(
        ITangibleNFT nft,
        IERC20 paymentToken,
        uint256[] calldata tokenIds,
        uint256[] calldata price
    ) external override {
        require(_checkToken(paymentToken), "NAT");
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            _sell(nft, paymentToken, tokenIds[i], price[i]);
        }
    }

    function sellFractionInitial(
        ITangibleNFT tnft,
        IERC20 paymentToken,
        uint256 tokenId,
        uint256 keepShare,
        uint256 sellShare,
        uint256 sellSharePrice,
        uint256 minPurchaseShare
    )
        external
        override
        returns (ITangibleFractionsNFT ftnft, uint256 tokenToSell)
    {
        address tokenOwner = msg.sender;
        require(tnft.ownerOf(tokenId) == tokenOwner, "NOW");
        require(_checkToken(paymentToken), "NAT");
        //take token from user

        tnft.safeTransferFrom(
            tokenOwner,
            address(this),
            tokenId,
            abi.encode(0, false)
        );
        //fractionalize
        //check if ftnft already deployed
        ftnft = factory.fractions(tnft, tokenId);
        if (address(ftnft) == address(0)) {
            ftnft = factory.newFractionTnft(tnft, tokenId);
        }
        //approve ftnft to take token
        tnft.approve(address(ftnft), tokenId);
        //set voucher
        MintInitialFractionVoucher memory voucher = MintInitialFractionVoucher({
            seller: tokenOwner,
            tnft: address(tnft),
            tnftTokenId: tokenId,
            keepShare: keepShare,
            sellShare: sellShare,
            sellPrice: sellSharePrice
        });
        (uint256 tokenToKeep, uint256 _tokenToSell) = factory.initialTnftSplit(
            voucher
        );
        tokenToSell = _tokenToSell;
        //adjust other data in lot
        marketplaceFract[address(ftnft)][tokenToSell]
            .minShare = minPurchaseShare;
        marketplaceFract[address(ftnft)][tokenToSell].price = sellSharePrice;
        marketplaceFract[address(ftnft)][tokenToSell].seller = tokenOwner;
        marketplaceFract[address(ftnft)][tokenToSell]
            .paymentToken = paymentToken;
        marketplaceFract[address(ftnft)][tokenToSell].initialShare = ftnft
            .fractionShares(tokenToSell);

        if (tokenToKeep > 0) {
            //initial token to keep is sent to marketplace,
            //so we need to delete it's record
            delete marketplaceFract[address(ftnft)][tokenToKeep];
            //update tracker
            updateTrackerFtnft(ftnft, tokenToKeep, false);
        }
        //to send usdc that marketplace received after fractionalizing
        IERC20 usdc = factory.USDC();
        usdc.safeTransfer(tokenOwner, usdc.balanceOf(address(this)));
        //delete record of tnft
        delete marketplace[address(tnft)][tokenId];
        //update tracker
        updateTrackerTnft(tnft, tokenId, false);
        return (ftnft, tokenToSell);
    }

    function updateTrackerFtnft(
        ITangibleFractionsNFT ftnft,
        uint256 tokenId,
        bool placed
    ) internal {
        onSaleTracker.ftnftSalePlaced(ftnft, tokenId, placed);
    }

    function updateTrackerTnft(
        ITangibleNFT tnft,
        uint256 tokenId,
        bool placed
    ) internal {
        onSaleTracker.tnftSalePlaced(tnft, tokenId, placed);
    }

    function buyFraction(
        ITangibleFractionsNFT ftnft,
        uint256 fractTokenId,
        uint256 share
    ) public {
        address buyer = msg.sender;
        address initialReSeller = factory.initReSeller();
        LotFract memory existing = marketplaceFract[address(ftnft)][
            fractTokenId
        ];
        uint256 remainingShare = ftnft.fractionShares(fractTokenId);
        require(
            (existing.seller != address(0)) && (remainingShare >= share),
            "NEFT"
        );
        //check if it is initial reseller and if the sale
        //is still ongoing
        if (existing.seller == initialReSeller) {
            require(
                IInitialReSellerExt(initialReSeller).canSellFractions(ftnft),
                "IREST"
            );
            if (factory.onlyWhitelistedForUnmintedCategory(ftnft.tnft())) {
                require(factory.whitelistForBuyUnminted(msg.sender), "NW");
            }
        }

        uint256 leftover = remainingShare - share;
        require(
            (share >= existing.minShare) &&
                (leftover == 0 || leftover >= existing.minShare),
            "IMP"
        );
        uint256 amount = (existing.price * share) / existing.initialShare;

        //take the fee
        IERC20 usdc = existing.paymentToken;

        uint256 toPaySeller = amount;
        //supporting fee per category
        uint256 _sellFee = feesPerCategory[ftnft.tnft()] == 0
            ? 250
            : feesPerCategory[ftnft.tnft()];
        if (
            _sellFee > 0 && factory.fractionToTnftAndId(ftnft).initialSaleDone
        ) {
            // if there is fee set, decrease amount by the fee and send fee
            uint256 fee = ((toPaySeller * _sellFee) / 10000);
            toPaySeller = toPaySeller - fee;
            usdc.safeTransferFrom(buyer, sellFeeAddress, fee);
            ISellFeeDistributor(sellFeeAddress).distributeFee(usdc, fee);
            emit MarketplaceFeePaid(address(ftnft), fractTokenId, fee);
        }
        usdc.safeTransferFrom(buyer, existing.seller, toPaySeller);

        if (share == remainingShare) {
            ftnft.safeTransferFrom(address(this), buyer, fractTokenId);

            emit SoldFract(
                existing.seller,
                address(ftnft),
                fractTokenId,
                amount
            );
            emit BoughtFract(
                buyer,
                address(ftnft),
                fractTokenId,
                existing.seller,
                amount
            );
            //set initial sale to be done if it is first time selling fraction and
            //through initial seller contract
            if (!factory.fractionToTnftAndId(ftnft).initialSaleDone) {
                //update payment data on reseller contract
                IInitialReSeller(factory.initReSeller()).updateBuyer(
                    ftnft,
                    buyer,
                    fractTokenId,
                    amount
                );
                //set flag that sale is done
                factory.initialSaleFinished(ftnft);
            }

            delete marketplaceFract[address(ftnft)][fractTokenId];
            //update tracker
            updateTrackerFtnft(ftnft, fractTokenId, false);
        } else {
            //we need to split and send to buyer
            uint256[] memory shares = new uint256[](2);
            shares[0] = leftover;
            shares[1] = share;
            uint256[] memory splitedTokens = ftnft.fractionalize(
                fractTokenId,
                shares
            );
            ftnft.safeTransferFrom(address(this), buyer, splitedTokens[1]);

            emit SoldFract(
                existing.seller,
                address(ftnft),
                splitedTokens[1],
                amount
            );
            emit BoughtFract(
                buyer,
                address(ftnft),
                splitedTokens[1],
                existing.seller,
                amount
            );

            delete marketplaceFract[address(ftnft)][splitedTokens[1]];
            //update tracker
            updateTrackerFtnft(ftnft, splitedTokens[1], false);
            //to send usdc that marketplace received after fractionalizing
            //we have revenue share and rent in USDC!
            factory.USDC().safeTransfer(
                existing.seller,
                usdc.balanceOf(address(this))
            );
            //if initial resseler
            if (existing.seller == factory.initReSeller()) {
                //update payment data on reseller contract
                IInitialReSeller(factory.initReSeller()).updateBuyer(
                    ftnft,
                    buyer,
                    splitedTokens[1],
                    amount
                );
            }
        }
    }

    function sellFraction(
        ITangibleFractionsNFT ftnft,
        IERC20 paymentToken,
        uint256 fractTokenId,
        uint256[] calldata shares,
        uint256 price,
        uint256 minPurchaseShare
    ) external {
        _sellFraction(
            ftnft,
            paymentToken,
            fractTokenId,
            shares,
            price,
            minPurchaseShare
        );
    }

    function _sellFraction(
        ITangibleFractionsNFT ftnft,
        IERC20 paymentToken,
        uint256 fractTokenId,
        uint256[] calldata shares,
        uint256 price,
        uint256 minPurchaseShare
    ) internal {
        address caller = msg.sender;
        LotFract memory existing = marketplaceFract[address(ftnft)][
            fractTokenId
        ];
        require(
            (ftnft.ownerOf(fractTokenId) == caller) ||
                (existing.seller == caller),
            "NOW"
        );
        require(_checkToken(paymentToken), "NAT");

        //this means that seller updates his sale
        if ((existing.tokenId == fractTokenId) && (existing.seller == caller)) {
            //update necessary info
            marketplaceFract[address(ftnft)][fractTokenId].price = price;
            marketplaceFract[address(ftnft)][fractTokenId]
                .minShare = minPurchaseShare;
        } else {
            //we have 2 cases - 1st selling whole share 2nd selling part of share
            uint256 length = shares.length;
            uint256 initialShare = ftnft.fractionShares(fractTokenId);
            require(length == 2, "WSH");
            //take the token
            ftnft.safeTransferFrom(
                caller,
                address(this),
                fractTokenId,
                abi.encode(price, true)
            );
            if (ftnft.fractionShares(fractTokenId) == shares[0]) {
                //1st case
                marketplaceFract[address(ftnft)][fractTokenId]
                    .minShare = minPurchaseShare;
                marketplaceFract[address(ftnft)][fractTokenId]
                    .initialShare = initialShare;
                marketplaceFract[address(ftnft)][fractTokenId]
                    .paymentToken = paymentToken;
            } else {
                uint256[] memory splitedTokens = ftnft.fractionalize(
                    fractTokenId,
                    shares
                );
                //return the keepToken to the caller
                ftnft.safeTransferFrom(address(this), caller, fractTokenId);
                delete marketplaceFract[address(ftnft)][fractTokenId];
                //update tracker
                updateTrackerFtnft(ftnft, fractTokenId, false);
                //update second piece
                LotFract memory lotFract = marketplaceFract[address(ftnft)][
                    splitedTokens[1]
                ];
                lotFract.price = price;
                lotFract.minShare = minPurchaseShare;
                lotFract.seller = caller;
                lotFract.paymentToken = paymentToken;
                marketplaceFract[address(ftnft)][splitedTokens[1]] = lotFract;
                //to send usdc that marketplace received after fractionalizing
                IERC20 usdc = factory.USDC();
                usdc.safeTransfer(caller, usdc.balanceOf(address(this)));
            }
        }
    }

    function _checkToken(IERC20 paymentToken) internal returns (bool) {
        return factory.paymentTokens(paymentToken);
    }

    function _sell(
        ITangibleNFT nft,
        IERC20 paymentToken,
        uint256 tokenId,
        uint256 price
    ) internal {
        //check who is the owner
        address ownerOfNft = IERC721(nft).ownerOf(tokenId);
        //if marketplace is owner and seller wants to update price
        if (
            (address(this) == ownerOfNft) &&
            (msg.sender == marketplace[address(nft)][tokenId].seller)
        ) {
            marketplace[address(nft)][tokenId].price = price;
        } else {
            //here we don't need to check, if not approved trx will fail
            nft.safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                abi.encode(price, false)
            );
            //set the desired payment token
            marketplace[address(nft)][tokenId].paymentToken = paymentToken;
        }
    }

    function setExchange(IExchange _exchange) external onlyAdmin {
        exchange = _exchange;
    }

    function setOnSaleTracker(IOnSaleTracker _onSaleTracker)
        external
        onlyAdmin
    {
        onSaleTracker = _onSaleTracker;
    }

    function setFactory(address _factory) external onlyAdmin {
        require(
            (_factory != address(0x0)) && (_factory != address(factory)),
            "WFA"
        );

        _grantRole(FACTORY_ROLE, _factory);
        _revokeRole(FACTORY_ROLE, address(factory));
        emit SetFactory(address(factory), _factory);
        factory = IFactoryExt(_factory);
    }

    function setFeeForCategory(ITangibleNFT tnft, uint256 fee)
        external
        onlyAdmin
    {
        //fees are 2 decimals 100% is 10000 2,5 is 250
        emit SellFeeChanged(tnft, feesPerCategory[tnft], fee);
        feesPerCategory[tnft] = fee;
    }

    /// @inheritdoc ITangibleMarketplace
    function stopBatchSale(ITangibleNFT nft, uint256[] calldata tokenIds)
        external
        override
    {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            _stopSale(nft, tokenIds[i]);
        }
    }

    function stopFractSale(ITangibleFractionsNFT ftnft, uint256 tokenId)
        external
    {
        address seller = msg.sender;
        // gas saving
        LotFract memory _lot = marketplaceFract[address(ftnft)][tokenId];
        require(_lot.seller == seller, "NOS");

        emit StopSellingFract(seller, address(ftnft), tokenId);
        delete marketplaceFract[address(ftnft)][tokenId];
        ftnft.safeTransferFrom(address(this), _lot.seller, _lot.tokenId);
        //update tracker
        updateTrackerFtnft(ftnft, tokenId, false);
    }

    function _stopSale(ITangibleNFT nft, uint256 tokenId) internal {
        address seller = msg.sender;
        // gas saving
        Lot memory _lot = marketplace[address(nft)][tokenId];
        require(_lot.seller == seller, "NOS");

        emit StopSelling(seller, address(nft), tokenId);
        delete marketplace[address(nft)][tokenId];
        IERC721(nft).safeTransferFrom(address(this), _lot.seller, _lot.tokenId);
        //update tracker
        updateTrackerTnft(nft, tokenId, false);
    }

    /// @inheritdoc ITangibleMarketplace
    function buy(
        ITangibleNFT nft,
        uint256 tokenId,
        uint256 _years
    ) external override {
        //pay for storage
        if (
            (!nft.isStorageFeePaid(tokenId) || _years > 0) &&
            nft.storageRequired()
        ) {
            require(_years > 0, "YZ");
            _payStorage(nft, tokenId, _years);
        }
        //buy the token
        _buy(nft, tokenId, true);
    }

    function payStorage(
        ITangibleNFT nft,
        uint256 tokenId,
        uint256 _years
    ) external override {
        _payStorage(nft, tokenId, _years);
    }

    function _payStorage(
        ITangibleNFT nft,
        uint256 tokenId,
        uint256 _years
    ) internal {
        require(nft.storageRequired(), "STNR");
        require(_years > 0, "YZ");

        uint256 amount = factory.adjustStorageAndGetAmount(
            nft,
            tokenId,
            _years
        );
        //we take in default USD token
        factory.defUSD().safeTransferFrom(
            msg.sender,
            factory.feeStorageAddress(),
            amount
        );
        emit StorageFeePaid(msg.sender, address(nft), tokenId, _years, amount);
    }

    /// @inheritdoc ITangibleMarketplace
    function buyUnminted(
        ITangibleNFT nft,
        uint256 _fingerprint,
        uint256 _years,
        bool onlyLock
    ) external override {
        if (factory.onlyWhitelistedForUnmintedCategory(nft)) {
            require(factory.whitelistForBuyUnminted(msg.sender), "NW");
        }
        IERC20 USDC = factory.defUSD();
        IERC20 TNGBL = factory.TNGBL();
        //buy unminted is always initial sale!!
        // need to also fetch stock here!! and remove remainingMintsForVendor
        (
            uint256 tokenPrice,
            uint256 stock,
            ,
            ,
            uint256 lockedAmount
        ) = _itemPrice(nft, IERC20Metadata(address(USDC)), _fingerprint, true);

        require((tokenPrice > 0) && (stock > 0), "!0S");

        MintVoucher memory voucher = MintVoucher({
            token: nft,
            mintCount: 1,
            price: 0,
            vendor: IOwnable(address(factory)).contractOwner(),
            buyer: msg.sender,
            fingerprint: _fingerprint,
            sendToVendor: false
        });
        uint256[] memory tokenIds = factory.mint(voucher);
        //pay for storage
        if (nft.storageRequired()) {
            _payStorage(nft, tokenIds[0], _years);
        }
        uint256 shouldLockTngbl = exchange.quoteOut(
            address(USDC),
            address(TNGBL),
            lockedAmount
        );
        if (factory.shouldLockTngbl(shouldLockTngbl) && !nft.paysRent()) {
            if (nft.tnftToPassiveNft(tokenIds[0]) == 0) {
                //convert locked amount to tngbl and send to nft contract
                //locktngbl can be called only from factory
                _lockTngbl(nft, tokenIds[0], lockedAmount, _years, onlyLock);
            }
        } else {
            USDC.safeTransferFrom(
                msg.sender,
                factory.feeStorageAddress(), //NOTE: or factory owner?
                lockedAmount
            );
        }
        marketplace[address(nft)][tokenIds[0]].paymentToken = USDC;
        //pricing should be handled from oracle
        _buy(voucher.token, tokenIds[0], false);
    }

    function _lockTngbl(
        ITangibleNFT nft,
        uint256 tokenId,
        uint256 lockedAmount,
        uint256 _years,
        bool onlyLock
    ) internal {
        IERC20 USDC = factory.defUSD();
        IERC20 TNGBL = factory.TNGBL();
        USDC.safeTransferFrom(msg.sender, address(this), lockedAmount);
        USDC.approve(address(exchange), lockedAmount);
        uint256 lockedTNGBL = exchange.exchange(
            address(USDC),
            address(TNGBL),
            lockedAmount,
            exchange.quoteOut(address(USDC), address(TNGBL), lockedAmount)
        );
        TNGBL.safeTransfer(address(nft), lockedTNGBL);
        factory.lockTNGBLOnTNFT(nft, tokenId, _years, lockedTNGBL, onlyLock);
    }

    function _itemPrice(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256 data,
        bool fromFingerprints
    )
        internal
        view
        returns (
            uint256 weSellAt,
            uint256 weSellAtStock,
            uint256 weBuyAt,
            uint256 weBuyAtStock,
            uint256 lockedAmount
        )
    {
        return
            fromFingerprints
                ? factory
                    .priceManager()
                    .getPriceOracleForCategory(nft)
                    .usdcPrice(nft, paymentUSDToken, data, 0)
                : factory
                    .priceManager()
                    .getPriceOracleForCategory(nft)
                    .usdcPrice(nft, paymentUSDToken, 0, data);
    }

    function _buy(
        ITangibleNFT nft,
        uint256 tokenId,
        bool chargeFee
    ) internal {
        // gas saving
        address buyer = msg.sender;

        Lot memory _lot = marketplace[address(nft)][tokenId];
        require(_lot.seller != address(0), "NLO");
        IERC20 USDC = _lot.paymentToken;

        // if lot.price == 0 it means vendor minted it, we must take price from oracle
        // if lot.price != 0 means some seller posted it and didn't want to use oracle
        uint256 cost = _lot.price;
        uint256 lockedAmount;
        if (cost == 0) {
            (cost, , , , lockedAmount) = _itemPrice(
                nft,
                IERC20Metadata(address(USDC)),
                tokenId,
                false
            );
            if (chargeFee) {
                //we called from buy function
                cost += lockedAmount;
                lockedAmount = 0;
            }
        }

        require(cost != 0, "P0");

        //take the fee
        uint256 toPayVendor = cost;
        uint256 _sellFee = feesPerCategory[nft] == 0
            ? 250
            : feesPerCategory[nft];
        if ((_sellFee > 0) && chargeFee) {
            // if there is fee set, decrease amount by the fee and send fee
            uint256 fee = ((toPayVendor * _sellFee) / 10000);
            toPayVendor = toPayVendor - fee;
            USDC.safeTransferFrom(buyer, sellFeeAddress, fee);
            ISellFeeDistributor(sellFeeAddress).distributeFee(USDC, fee);
            emit MarketplaceFeePaid(address(nft), tokenId, fee);
        }

        USDC.safeTransferFrom(buyer, _lot.seller, toPayVendor);

        emit Sold(_lot.seller, address(nft), tokenId, cost);
        emit Bought(
            buyer,
            address(nft),
            tokenId,
            _lot.seller,
            cost + lockedAmount
        );
        delete marketplace[address(nft)][tokenId];
        //update tracker
        updateTrackerTnft(nft, tokenId, false);

        nft.safeTransferFrom(address(this), buyer, tokenId);
    }

    /// @notice Sets the feeStorageAddress
    /// @dev Will emit SellFeeAddressSet on change.
    /// @param _sellFeeAddress A new address for fee storage.
    function setSellFeeAddress(address _sellFeeAddress) external onlyAdmin {
        emit SellFeeAddressSet(sellFeeAddress, _sellFeeAddress);
        sellFeeAddress = _sellFeeAddress;
    }

    function onERC721Received(
        address operator,
        address seller,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return _onERC721Received(operator, seller, tokenId, data);
    }

    function _onERC721Received(
        address, /*operator*/
        address seller,
        uint256 tokenId,
        bytes calldata data
    ) private returns (bytes4) {
        address nft = msg.sender;
        (uint256 price, bool fraction) = abi.decode(data, (uint256, bool));
        IERC20 USDC = factory.defUSD();

        if (!fraction) {
            marketplace[nft][tokenId] = Lot(
                ITangibleNFT(nft),
                USDC,
                tokenId,
                seller,
                price,
                true
            );
            emit Selling(seller, nft, tokenId, price);
            updateTrackerTnft(ITangibleNFT(nft), tokenId, true);
        } else {
            marketplaceFract[nft][tokenId] = LotFract(
                ITangibleFractionsNFT(nft),
                USDC,
                tokenId,
                seller,
                price,
                0, //set later minPurchaseShare
                ITangibleFractionsNFT(nft).fractionShares(tokenId) //set later initialShare
            );
            emit SellingFract(seller, nft, tokenId, price);
            updateTrackerFtnft(ITangibleFractionsNFT(nft), tokenId, true);
        }

        return IERC721Receiver.onERC721Received.selector;
    }
}
