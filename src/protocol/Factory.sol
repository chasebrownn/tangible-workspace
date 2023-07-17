// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../abstract/AdminAndTangibleAccess.sol";
import "../interfaces/IFactory.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ITangiblePriceManager.sol";
import "../interfaces/ITangibleNFTDeployer.sol";
import "../interfaces/ITangibleFractionsNFTDeployer.sol";
import "../interfaces/IFractionStorageManagerDeployer.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IFractionStorageManager.sol";
import "../interfaces/IOwnable.sol";
import "../interfaces/IInitialReSeller.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IInitialReSellerExt is IInitialReSeller {
    function saleData(ITangibleFractionsNFT ftnft)
        external
        view
        returns (FractionSaleData memory);
}

contract Factory is IFactory, IOwnable {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    enum FACT_ADDRESSES {
        MARKETPLACE, //0
        TNFT_DEPLOYER, //1
        FTNFT_DEPLOYER, //2
        PASSIVE_NFT, //3
        STORAGE_DEPLOYER, //4
        INSTANT_LIQUIDITY, //5
        REVENUE_SHARE, //6
        RENT_SHARE, //7
        TNGBL, //8
        DAO, //9
        FEE_STORAGE, //10
        PRICE_MANAGER, //11
        INIT_RE_SELLER, //12
        LAST
    }
    //for revenue share
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER"); // 32
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR"); // 32
    bytes32 public constant SHARE_MANAGER_ROLE = keccak256("SHARE_MANAGER"); // 32
    //for piNFT
    bytes32 public constant REVENUE_MANAGER_ROLE = keccak256("REVENUE_MANAGER"); // 32

    address internal _contractOwner; // 20
    address internal _newContractOwner; // 20

    //USDC contract address, necessary for revenueShare contract
    IERC20 public immutable override USDC; // 20
    //default USD contract - token used for buying unminted and paying storage
    IERC20 public override defUSD; // 20
    address public instantLiquidity; // 20
    //passive income data
    RevenueShare public override revenueShare; // 20
    RentShare public override rentShare; // 20
    IERC20 public override TNGBL; // 20
    PassiveIncomeNFT public override passiveNft; // 20

    address public override feeStorageAddress; // 20
    address public override marketplace; // 20
    address public override deployer; // 20
    address public fractionsDeployer; // 20
    address public storageDeployer; // 20

    address public override tangibleDao; // 20

    address public override initReSeller; // 20

    mapping(IERC20 => bool) public paymentTokens;

    mapping(ITangibleNFT => bool)
        public
        override onlyWhitelistedForUnmintedCategory;
    mapping(address => bool) public override whitelistForBuyUnminted;

    mapping(string => ITangibleNFT) public override category;
    mapping(ITangibleNFT => mapping(uint256 => ITangibleFractionsNFT))
        public
        override fractions;
    mapping(ITangibleFractionsNFT => TnftWithId) public fractionToTnftAndId;

    ITangibleNFT[] private _tnfts;
    ITangibleFractionsNFT[] private _tnftsFractions;
    ITangiblePriceManager public override priceManager;

    //to be used in contract upgrades
    uint256 public majorityFractionShare = 6600000; //66%
    uint256 public majorityAboveMarket = 11000; //110% 100% -> 10000

    mapping(ITangibleFractionsNFT => IFractionStorageManager)
        public storageManagers;

    modifier onlyOwner() {
        require(
            _contractOwner == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }

    modifier onlyMarketplace() {
        require(
            marketplace == msg.sender,
            "Factory: caller is not the marketplace"
        );
        _;
    }

    modifier onlyOwnerOrMarketplace() {
        require(
            (_contractOwner == msg.sender) || (marketplace == msg.sender),
            "Factory: caller is not the owner nor marketplace"
        );
        _;
    }

    modifier onlyOwnerOrInstantLiquidity() {
        require(
            (_contractOwner == msg.sender) || (instantLiquidity == msg.sender),
            "Factory: caller is not the owner nor instantLiquidity"
        );
        _;
    }

    function isOwner(address account) internal view returns (bool) {
        return _contractOwner == account;
    }

    function isMarketplace(address account) internal view returns (bool) {
        return marketplace == account;
    }

    /// @dev Restricted to owner.
    constructor(
        address _usdc,
        address _feeStorageAddress,
        address _priceManager
    ) {
        require(_usdc != address(0), "UZ");

        USDC = IERC20(_usdc);
        defUSD = IERC20(_usdc);
        paymentTokens[IERC20(_usdc)] = true;

        feeStorageAddress = _feeStorageAddress;
        priceManager = ITangiblePriceManager(_priceManager);

        _contractOwner = msg.sender;

        emit OwnershipPushed(address(0), _contractOwner);
    }

    function setMajorityTakeoverPercentage(uint256 _majorityPercentage)
        external
        onlyOwner
    {
        require(_majorityPercentage > 5000000, "INCP");
        majorityFractionShare = _majorityPercentage;
    }

    function setMajorityAboveMarketPercentage(uint256 _majorityMarketPercentage)
        external
        onlyOwner
    {
        require(_majorityMarketPercentage > 10000, "INCP");
        majorityAboveMarket = _majorityMarketPercentage;
    }

    function setDefaultStableUSD(IERC20 usd) external onlyOwner {
        require(paymentTokens[usd], "NAPP");
        defUSD = usd;
    }

    function setContract(FACT_ADDRESSES _contractId, address _contractAddress)
        external
        onlyOwner
    {
        _setContract(_contractId, _contractAddress);
    }

    function configurePaymentToken(IERC20 token, bool value)
        external
        onlyOwner
    {
        paymentTokens[token] = value;
        emit PaymentToken(address(token), value);
    }

    function _setContract(FACT_ADDRESSES _contractId, address _contractAddress)
        internal
    {
        require(
            (_contractId >= FACT_ADDRESSES.MARKETPLACE) &&
                (_contractId < FACT_ADDRESSES.LAST),
            "WID"
        );
        require(_contractAddress != address(0), "WADD");
        if (_contractId == FACT_ADDRESSES.MARKETPLACE) {
            //0
            marketplace = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.TNFT_DEPLOYER) {
            //1
            deployer = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.FTNFT_DEPLOYER) {
            //2
            fractionsDeployer = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.PASSIVE_NFT) {
            // 3
            passiveNft = PassiveIncomeNFT(_contractAddress);
        } else if (_contractId == FACT_ADDRESSES.STORAGE_DEPLOYER) {
            //4
            storageDeployer = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.INSTANT_LIQUIDITY) {
            //5
            instantLiquidity = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.REVENUE_SHARE) {
            //6
            revenueShare = RevenueShare(_contractAddress);
        } else if (_contractId == FACT_ADDRESSES.RENT_SHARE) {
            //7
            rentShare = RentShare(_contractAddress);
        } else if (_contractId == FACT_ADDRESSES.TNGBL) {
            //8
            TNGBL = IERC20(_contractAddress);
        } else if (_contractId == FACT_ADDRESSES.DAO) {
            //9
            tangibleDao = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.FEE_STORAGE) {
            //10
            feeStorageAddress = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.PRICE_MANAGER) {
            //11
            priceManager = ITangiblePriceManager(_contractAddress);
        } else if (_contractId == FACT_ADDRESSES.INIT_RE_SELLER) {
            //12
            initReSeller = _contractAddress;
        }
    }

    function getCategories() external view returns (ITangibleNFT[] memory) {
        return _tnfts;
    }

    function getFractions()
        external
        view
        returns (ITangibleFractionsNFT[] memory)
    {
        return _tnftsFractions;
    }

    /// @inheritdoc IFactory
    function isFactoryOperator(address operator)
        external
        view
        override
        returns (bool)
    {
        return isOwner(operator);
    }

    /// @inheritdoc IFactory
    function isFactoryAdmin(address admin)
        external
        view
        override
        returns (bool)
    {
        return isOwner(admin);
    }

    function adjustStorageAndGetAmount(
        ITangibleNFT tnft,
        uint256 tokenId,
        uint256 _years
    ) external override onlyMarketplace returns (uint256) {
        (uint256 tokenPrice, , , , ) = _itemPrice(
            tnft,
            IERC20Metadata(address(defUSD)),
            tokenId,
            false
        );

        return tnft.adjustStorageAndGetAmount(tokenId, _years, tokenPrice);
    }

    function payTnftStorageWithManager(
        ITangibleNFT tnft,
        uint256 tokenId,
        uint256 _years
    ) external override {
        //take sender
        address sender = msg.sender;
        //extract fract for comparison of sender and stored manager
        ITangibleFractionsNFT fract = IFractionStorageManager(sender)
            .fracTnft();
        require(address(storageManagers[fract]) == sender, "NAP");
        //add check if storage manager
        (uint256 tokenPrice, , , , ) = _itemPrice(
            tnft,
            IERC20Metadata(address(defUSD)),
            tokenId,
            false
        );
        uint256 amount = tnft.adjustStorageAndGetAmount(
            tokenId,
            _years,
            tokenPrice
        );
        //pay in default usd token
        defUSD.safeTransferFrom(msg.sender, feeStorageAddress, amount);
    }

    function lockTNGBLOnTNFT(
        ITangibleNFT tnft,
        uint256 tokenId,
        uint256 _years,
        uint256 lockedAmountTNGBL,
        bool onlyLock
    ) external override onlyMarketplace {
        tnft.lockTNGBL(tokenId, _years, lockedAmountTNGBL, onlyLock);
    }

    function decreaseInstantLiquidityStock(
        ITangibleNFT nft,
        uint256 fingerprint
    ) external override onlyOwnerOrInstantLiquidity {
        priceManager.getPriceOracleForCategory(nft).decrementBuyStock(
            fingerprint
        );
    }

    /// @notice Mints the TangibleNFT token from the given MintVoucher
    /// @dev Will revert if the signature is invalid.
    /// @param voucher An MintVoucher describing an unminted TangibleNFT.
    function mint(MintVoucher calldata voucher)
        external
        override
        onlyOwnerOrMarketplace
        returns (uint256[] memory)
    {
        // make sure signature is valid and get the address of the vendor
        require(marketplace != address(0), "MZ");
        //make sure that vendor(who is not admin nor marketplace) is minting just for himself
        uint256 mintCount = 1;
        if (!isMarketplace(msg.sender)) {
            require(voucher.vendor == msg.sender, "MFSE");
            mintCount = voucher.mintCount;
        } else if (isMarketplace(msg.sender)) {
            require(voucher.buyer != address(0), "BMNBZ");
            require(isOwner(voucher.vendor), "MFSEO");
            //houses can't be bought by marketplace unless
            if (voucher.token.paysRent()) {
                require(
                    onlyWhitelistedForUnmintedCategory[voucher.token],
                    "OWL"
                );
            }
        }
        (uint256 sellStock, ) = priceManager
            .getPriceOracleForCategory(voucher.token)
            .availableInStock(voucher.fingerprint);
        require(sellStock > 0, "Not enough in stock");

        // first assign the token to the vendor, to establish provenance on-chain
        uint256[] memory tokenIds = voucher.token.produceMultipleTNFTtoStock(
            mintCount,
            voucher.fingerprint,
            voucher.vendor
        );
        emit MintedTokens(address(voucher.token), tokenIds);

        //option only available to owner to mint and get in his own wallet (eg. realestate)
        address transferTo = marketplace;
        if (voucher.sendToVendor && isOwner(msg.sender)) {
            transferTo = msg.sender;
        }

        // send minted tokens to marketplace. when price is 0 - use oracle
        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i++) {
            IERC721(voucher.token).safeTransferFrom(
                voucher.vendor,
                transferTo,
                tokenIds[i],
                abi.encode(voucher.price, false)
            );
            //decrease stock
            priceManager
                .getPriceOracleForCategory(voucher.token)
                .decrementSellStock(voucher.fingerprint);
        }

        return tokenIds;
    }

    //redeem nft toggle - set the status of tnft as indication that user redeemed his
    //tnft and that it can't be used in sales or vice-versa
    function redeemToggle(RedeemVoucher calldata voucher)
        external
        override
        onlyOwner
    {
        voucher.token.setTNFTStatuses(voucher.tokenIds, voucher.inOurCustody);
    }

    function _roleGranter(
        address granter,
        address to,
        bytes32 roleToGrant
    ) internal {
        AccessControl(granter).grantRole(roleToGrant, to);
    }

    /// just for migration puproses, we must avoid unnecessary deployments on new factories
    function setCategory(
        string calldata name,
        ITangibleNFT nft,
        address priceOracle
    ) external override onlyOwner {
        require(address(category[name]) == address(0), "CEZ");
        category[name] = nft;
        _tnfts.push(nft);

        //for revenue share
        _roleGranter(address(revenueShare), address(nft), SHARE_MANAGER_ROLE);
        //for rent share
        _roleGranter(address(rentShare), address(nft), SHARE_MANAGER_ROLE);
        //for piNFT
        _roleGranter(address(passiveNft), address(nft), REVENUE_MANAGER_ROLE);

        //set the oracle
        ITangiblePriceManager(priceManager).setOracleForCategory(
            nft,
            IPriceOracle(priceOracle)
        );

        emit NewCategoryDeployed(address(nft));
    }

    function setFraction(
        ITangibleNFT nft,
        ITangibleFractionsNFT fraction,
        uint256 tnftTokenId,
        bool initSaleDone
    ) external onlyOwner {
        require(address(fractions[nft][tnftTokenId]) == address(0), "FEZ");
        fractions[nft][tnftTokenId] = fraction;
        //to do mapping fraction -> tnft
        fractionToTnftAndId[fraction] = TnftWithId({
            tnft: nft,
            tnftTokenId: tnftTokenId,
            initialSaleDone: initSaleDone
        });
        _tnftsFractions.push(fraction);

        //for revenue share
        _roleGranter(
            address(revenueShare),
            address(fraction),
            SHARE_MANAGER_ROLE
        );
        //for rent share
        _roleGranter(address(rentShare), address(fraction), SHARE_MANAGER_ROLE);
        //for piNFT
        _roleGranter(
            address(passiveNft),
            address(fraction),
            REVENUE_MANAGER_ROLE
        );

        emit NewFractionDeployed(address(fraction));
    }

    function newCategory(
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        address priceOracle,
        uint256 _lockPercentage,
        bool _paysRent
    ) external override onlyOwner returns (ITangibleNFT) {
        require(address(category[name]) == address(0), "CE");
        require(deployer != address(0), "Deployer zero");
        ITangibleNFT tangibleNFT = ITangibleNFTDeployer(deployer).deployTnft(
            msg.sender,
            name,
            symbol,
            uri,
            isStoragePriceFixedAmount,
            storageRequired,
            _lockPercentage,
            _paysRent
        );
        category[name] = tangibleNFT;
        _tnfts.push(tangibleNFT);

        //for revenue share
        _roleGranter(
            address(revenueShare),
            address(tangibleNFT),
            SHARE_MANAGER_ROLE
        );
        //for rent share
        _roleGranter(
            address(rentShare),
            address(tangibleNFT),
            SHARE_MANAGER_ROLE
        );
        if (_paysRent) {
            _roleGranter(address(rentShare), address(tangibleNFT), bytes32(0));
        }
        //for piNFT
        _roleGranter(
            address(passiveNft),
            address(tangibleNFT),
            REVENUE_MANAGER_ROLE
        );

        //set the oracle
        ITangiblePriceManager(priceManager).setOracleForCategory(
            tangibleNFT,
            IPriceOracle(priceOracle)
        );

        emit NewCategoryDeployed(address(tangibleNFT));
        return tangibleNFT;
    }

    function newFractionTnft(ITangibleNFT _tnft, uint256 _tnftTokenId)
        external
        override
        onlyMarketplace
        returns (ITangibleFractionsNFT)
    {
        require(address(fractions[_tnft][_tnftTokenId]) == address(0), "FEX");
        require(fractionsDeployer != address(0), "Deployer zero");

        string memory name = string(
            abi.encodePacked(_tnft.name(), "F_", _tnftTokenId.toString())
        );
        string memory symbol = string(
            abi.encodePacked(
                _tnft.symbol(),
                "_",
                _tnft.tokensFingerprint(_tnftTokenId).toString()
            )
        );

        RevenueShare rentShare_ = _tnft.paysRent()
            ? rentShare.forToken(address(_tnft), _tnftTokenId)
            : RevenueShare(address(0));
        //call storage manager contract deployer
        IFractionStorageManager manager = IFractionStorageManagerDeployer(
            storageDeployer
        ).deployStorageManagerTnft(address(_tnft), address(this), _tnftTokenId);

        ITangibleFractionsNFT tangibleFractNFT = ITangibleFractionsNFTDeployer(
            fractionsDeployer
        ).deployFractionTnft(
                tangibleDao, //dao is the owner
                address(_tnft),
                address(manager),
                address(rentShare_),
                _tnftTokenId,
                name,
                symbol
            );
        //store storageManager
        storageManagers[tangibleFractNFT] = manager;

        if (address(rentShare_) != address(0)) {
            _tnft.setRolesForFraction(address(tangibleFractNFT), _tnftTokenId);
        }

        fractions[_tnft][_tnftTokenId] = tangibleFractNFT;
        //to do mapping fraction -> tnft
        fractionToTnftAndId[tangibleFractNFT] = TnftWithId({
            tnft: _tnft,
            tnftTokenId: _tnftTokenId,
            initialSaleDone: _tnft.paysRent() ? false : true //if no rent - set always to true
        });
        _tnftsFractions.push(tangibleFractNFT);
        //must be after setting fractions
        manager.adjustFTNFT();

        //for revenue share
        if (_tnft.tnftToPassiveNft(_tnftTokenId) != 0) {
            _roleGranter(
                address(revenueShare),
                address(tangibleFractNFT),
                SHARE_MANAGER_ROLE
            );
            _roleGranter(
                address(revenueShare),
                address(tangibleFractNFT),
                CLAIMER_ROLE
            );
        }
        //for piNFT
        _roleGranter(
            address(passiveNft),
            address(tangibleFractNFT),
            REVENUE_MANAGER_ROLE
        );

        emit NewFractionDeployed(address(tangibleFractNFT));
        return tangibleFractNFT;
    }

    function initialTnftSplit(MintInitialFractionVoucher calldata voucher)
        external
        override
        onlyOwnerOrMarketplace
        returns (uint256 tokenKeep, uint256 tokenSell)
    {
        ITangibleFractionsNFT ftnft = fractions[ITangibleNFT(voucher.tnft)][
            voucher.tnftTokenId
        ];
        require(address(ftnft) != address(0), "FNE");
        (tokenKeep, tokenSell) = ftnft.initialSplit(
            msg.sender,
            voucher.tnft,
            voucher.tnftTokenId,
            voucher.keepShare,
            voucher.sellShare
        );
        fractions[ITangibleNFT(voucher.tnft)][voucher.tnftTokenId] = ftnft;
        //send tokenKeep to the seler
        if (tokenKeep > 0) {
            ftnft.safeTransferFrom(msg.sender, voucher.seller, tokenKeep);
        }

        emit InitialFract(address(ftnft), tokenKeep, tokenSell);
    }

    function updateOracleForTnft(string calldata name, address priceOracle)
        external
        override
        onlyOwner
    {
        require(address(category[name]) != address(0), "CNE");
        ITangiblePriceManager(priceManager).setOracleForCategory(
            category[name],
            IPriceOracle(priceOracle)
        );
    }

    function whitelistBuyer(address buyer, bool approved) external onlyOwner {
        whitelistForBuyUnminted[buyer] = approved;
        emit WhitelistedBuyer(buyer, approved);
    }

    function setRequireWhitelistCategory(ITangibleNFT nft, bool required)
        external
        onlyOwner
    {
        onlyWhitelistedForUnmintedCategory[nft] = required;
    }

    function shouldLockTngbl(uint256 tngblAmount)
        external
        view
        override
        returns (bool)
    {
        return passiveNft.canEarnForAmount(tngblAmount);
    }

    function seizeTnft(ITangibleNFT tnft, uint256[] memory tokenIds)
        external
        onlyOwner
    {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 token = tokenIds[i];
            bool ableToSeize = tnft.storageEndTime(token) + 180 days <
                block.timestamp;
            require(ableToSeize);

            address ownerTnft = tnft.ownerOf(token);
            tnft.safeTransferFrom(ownerTnft, _contractOwner, token);
        }
    }

    function takeFtnftForReemburse(
        ITangibleFractionsNFT ftnft,
        uint256 fractionId
    ) external {
        require(msg.sender == initReSeller, "NA");
        ftnft.safeTransferFrom(
            ftnft.ownerOf(fractionId),
            initReSeller,
            fractionId
        );
    }

    function seizeFractionTnft(
        ITangibleFractionsNFT ftnft,
        uint256[] calldata fractionTokenIds
    ) external onlyOwner {
        uint256 length = fractionTokenIds.length;

        ITangibleNFT tnft = ftnft.tnft();
        IFractionStorageManager manager = storageManagers[ftnft];
        uint256 tnftTokenId = ftnft.tnftTokenId();
        bool ninetyPassed = (tnft.storageEndTime(tnftTokenId) + 90 days <
            block.timestamp);

        require(ninetyPassed);

        for (uint256 i = 0; i < length; i++) {
            uint256 token = fractionTokenIds[i];
            bool ableToSeize = !manager.canTransfer(token);
            require(ableToSeize);

            address ownerFTnft = ftnft.ownerOf(token);
            ftnft.safeTransferFrom(ownerFTnft, _contractOwner, token);
        }
    }

    function majorityShareTakeover(
        ITangibleFractionsNFT ftnft,
        uint256 holdingFraction,
        uint256[] calldata otherFractions
    ) external {
        address majorityOwner = msg.sender;

        require(majorityOwner == ftnft.ownerOf(holdingFraction), "Not owner");
        require(
            ftnft.fractionShares(holdingFraction) >= majorityFractionShare,
            "Not majority"
        );
        require(fractionToTnftAndId[ftnft].initialSaleDone, "SaleIP");

        ITangibleNFT tnft = ftnft.tnft();
        uint256 fingerprint = ftnft.tnftFingerprint();
        //take market price weSellAt + lockedAmount = whole tokenPrice
        (uint256 weSellAt, , , , uint256 lockedAmount) = _itemPrice(
            tnft,
            IERC20Metadata(address(defUSD)),
            fingerprint,
            true
        );
        //increase it to aboveMarketPrice
        uint256 aboveMarketPrice = ((weSellAt + lockedAmount) *
            majorityAboveMarket) / 10000;

        _takeAndPay(ftnft, otherFractions, aboveMarketPrice, majorityOwner);
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
                ? priceManager.getPriceOracleForCategory(nft).usdcPrice(
                    nft,
                    paymentUSDToken,
                    data,
                    0
                )
                : priceManager.getPriceOracleForCategory(nft).usdcPrice(
                    nft,
                    paymentUSDToken,
                    0,
                    data
                );
    }

    function initialSaleFinished(ITangibleFractionsNFT ftnft)
        external
        override
        onlyMarketplace
    {
        fractionToTnftAndId[ftnft].initialSaleDone = true;
        //complete the sale, and send the money of sale
        IInitialReSeller(initReSeller).completeSale(ftnft);
    }

    function _takeAndPay(
        ITangibleFractionsNFT ftnft,
        uint256[] calldata otherFractions,
        uint256 marketPrice,
        address owner
    ) internal {
        uint256 length = otherFractions.length;
        uint256 fullShare = ftnft.fullShare();

        for (uint256 i = 0; i < length; i++) {
            //calc how much to transfer
            uint256 usdcToTransfer = (marketPrice *
                ftnft.fractionShares(otherFractions[i])) / fullShare;
            require(
                (marketplace != ftnft.ownerOf(otherFractions[i])) &&
                    instantLiquidity != ftnft.ownerOf(otherFractions[i]),
                "BMKT"
            );
            //transfer the money
            defUSD.safeTransferFrom(
                owner,
                ftnft.ownerOf(otherFractions[i]),
                usdcToTransfer
            );
            //do the claims
            ftnft.claimFor(address(ftnft), otherFractions[i]);
            //take the ftnft
            ftnft.safeTransferFrom(
                ftnft.ownerOf(otherFractions[i]),
                owner,
                otherFractions[i]
            );
        }
    }

    function contractOwner() public view override returns (address) {
        return _contractOwner;
    }

    function renounceOwnership() public virtual override onlyOwner {
        emit OwnershipPushed(_contractOwner, address(0));
        _contractOwner = address(0);
    }

    function pushOwnership(address newOwner_)
        public
        virtual
        override
        onlyOwner
    {
        require(
            newOwner_ != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipPushed(_contractOwner, newOwner_);
        _newContractOwner = newOwner_;
    }

    function pullOwnership() public virtual override {
        require(
            msg.sender == _newContractOwner,
            "Ownable: must be new owner to pull"
        );

        emit OwnershipPulled(_contractOwner, _newContractOwner);
        _contractOwner = _newContractOwner;
    }
}
