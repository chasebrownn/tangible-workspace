// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/IInstantLiquidity.sol";
import "../interfaces/IILCalculator.sol";
import "../interfaces/ITNGBLOracle.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ITangiblePriceManager.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IExchange.sol";
import "../interfaces/IOnSaleTracker.sol";
import "../interfaces/ITangibleMarketplace.sol";
import "../abstract/AdminAndTangibleAccess.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFactoryExt is IFactory {
    function fractionToTnftAndId(ITangibleFractionsNFT fraction)
        external
        view
        returns (TnftWithId memory);

    function paymentTokens(IERC20 token) external returns (bool);
}

interface IOnSaleTrackerExt is IOnSaleTracker {
    struct ContractItem {
        bool selling;
        uint256 index;
    }

    function isFtnftOnSale(ITangibleFractionsNFT ftnft)
        external
        view
        returns (ContractItem memory);
}

contract InstantLiquidity is
    IInstantLiquidity,
    AdminAndTangibleAccess,
    IERC721Receiver
{
    enum PAYMENT_TOKEN {
        USDC,
        TNGBL,
        LAST
    }
    using SafeERC20 for IERC20;
    IExchange public exchange;
    address public factory;

    address public instantCalculator;
    ITNGBLOracle public tngblOracle;
    IOnSaleTrackerExt public onSaleTracker;

    IERC20 public defaultToken;

    bool public instantAllowed;
    uint256 public instantAllowedTimestamp;

    mapping(address => mapping(uint256 => InstantLot))
        private instantMarketplace;

    modifier onlyFactoryAdmin() {
        IFactory(factory).isFactoryAdmin(msg.sender);
        _;
    }

    constructor() {
        instantAllowed = false;
    }

    function setPaymentTokenDefault(IERC20 token) external onlyFactoryAdmin {
        require(IFactoryExt(factory).paymentTokens(token), "NAT");
        defaultToken = token;
        emit DefaultToken(token);
    }

    /// @notice Sets the IExchange address
    /// @dev Will emit MarketplaceAddressSet on change.
    /// @param _exchange A new address of the Marketplace
    function setExchange(address _exchange) external onlyFactoryAdmin {
        emit ExchangeAddressSet(address(exchange), _exchange);
        exchange = IExchange(_exchange);
    }

    /// @notice Sets the IFactory address
    /// @dev Will emit FactoryAddressSet on change.
    /// @param _factory A new address of the Factory
    function setFactory(address _factory) external onlyAdmin {
        require(_factory != address(0), "ZMA");

        emit FactoryAddressSet(factory, _factory);
        factory = _factory;
    }

    /// @notice Sets the ITNGBLOracle address
    /// @dev Will emit TNGBLOracleAddressSet on change.
    /// @param _oracle A new address of the TNGBLOracle
    function setTNGBLOracle(address _oracle) external onlyFactoryAdmin {
        require(_oracle != address(0), "ZMA");

        emit TNGBLOracleAddressSet(address(tngblOracle), _oracle);
        tngblOracle = ITNGBLOracle(_oracle);
    }

    function setInstantTrade(bool allowed) external onlyFactoryAdmin {
        instantAllowed = allowed;
        instantAllowedTimestamp = block.timestamp;
    }

    /// @notice Sets the IILCalculator address
    /// @dev Will emit IILCalculator on change.
    /// @param _calculator A new address of the TNGBLOracle
    function setInstantCalculator(address _calculator)
        external
        onlyFactoryAdmin
    {
        require(_calculator != address(0), "ZMA");

        emit IILCalculatorAddressSet(instantCalculator, _calculator);
        instantCalculator = _calculator;
    }

    function setOnSaleTracker(IOnSaleTrackerExt _onSaleTracker)
        external
        onlyFactoryAdmin
    {
        onSaleTracker = _onSaleTracker;
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

    function _sanityChecks(
        ITangibleNFT _nft,
        address _ftnft,
        uint256 _fingerprint,
        bool _sellInstant
    ) internal returns (uint256 priceToPay) {
        bool defIsUSD = !(defaultToken == IFactory(factory).TNGBL());
        if (!defIsUSD) {
            //it is TNGBL
            _volatilityCheck();
        }
        //for price check - if tngbl use usdc, rest default token
        IERC20 forPrice = defIsUSD ? defaultToken : IFactory(factory).defUSD();
        // get tnft token price
        (
            uint256 weSellAt,
            ,
            uint256 weBuyAt,
            uint256 weBuyAtStock,
            uint256 lockedAmount
        ) = _itemPrice(
                _nft,
                IERC20Metadata(address(forPrice)),
                _fingerprint,
                true
            );
        if (_sellInstant) {
            if (_ftnft != address(0)) {
                if (
                    !onSaleTracker
                        .isFtnftOnSale(ITangibleFractionsNFT(_ftnft))
                        .selling
                ) {
                    require(weBuyAtStock > 0, "Not purchasable");
                    //decrease weBuyAtStock
                    IFactory(factory).decreaseInstantLiquidityStock(
                        _nft,
                        _fingerprint
                    );
                }
            } else {
                require(weBuyAtStock > 0, "Not purchasable");
            }
        } else {
            //calc
            if (_nft.paysRent()) {
                weBuyAt = weSellAt + lockedAmount;
            } else {
                weBuyAt = IILCalculator(instantCalculator).calculateILPrice(
                    weSellAt,
                    weBuyAt
                );
            }
        }
        // get price to pay
        priceToPay = defIsUSD ? weBuyAt : _getUSDCToTNGBL(weBuyAt);
        // check whether this contract has defToken for liquidity
        require(
            IERC20(defaultToken).balanceOf(address(this)) >= priceToPay,
            "Funds low"
        );
    }

    function sellInstant(
        ITangibleNFT _nft,
        uint256 _fingerprint,
        uint256 _tokenId
    ) external override {
        require(instantAllowed, "Trading stopped");
        require(
            (instantAllowedTimestamp + 1 hours) < block.timestamp,
            "One hr not passed"
        );
        require(_nft.ownerOf(_tokenId) == msg.sender, "Not owner");
        require(
            _nft.tokensFingerprint(_tokenId) == _fingerprint,
            "Wrong fingerprint"
        );

        uint256 priceToPay = _sanityChecks(
            _nft,
            address(0),
            _fingerprint,
            true
        );
        // transfer NFT to this contract
        _nft.safeTransferFrom(msg.sender, address(this), _tokenId);
        // transfer token to seller
        IERC20(defaultToken).safeTransfer(msg.sender, priceToPay);
        //decrease weBuyAtStock
        IFactory(factory).decreaseInstantLiquidityStock(_nft, _fingerprint);

        // make a sale here set instantmarketplace.
        instantMarketplace[address(_nft)][_tokenId] = InstantLot(
            address(_nft),
            _tokenId,
            address(this),
            false
        );
        //update tracker
        updateTrackerTnft(_nft, _tokenId, true);
    }

    function buyInstant(ITangibleNFT _nft, uint256 _tokenId) external override {
        require(instantAllowed, "Trading stopped");
        require(
            (instantAllowedTimestamp + 1 hours) < block.timestamp,
            "One hr not passed"
        );
        require(
            instantMarketplace[address(_nft)][_tokenId].nft != address(0),
            "No lot"
        );

        uint256 priceToTake = _sanityChecks(
            _nft,
            address(0),
            _nft.tokensFingerprint(_tokenId),
            false
        );
        //take token
        IERC20(defaultToken).safeTransferFrom(
            msg.sender,
            address(this),
            priceToTake
        );
        //send the nft to buyer
        IERC721(_nft).safeTransferFrom(address(this), msg.sender, _tokenId);

        delete instantMarketplace[address(_nft)][_tokenId];
        //update tracker
        updateTrackerTnft(_nft, _tokenId, false);
    }

    function sellInstantFraction(
        ITangibleFractionsNFT _ftnft,
        uint256 _tokenIdFract
    ) external override {
        require(instantAllowed, "Trading stopped");
        require(
            (instantAllowedTimestamp + 1 hours) < block.timestamp,
            "One hr not passed"
        );
        require(_ftnft.ownerOf(_tokenIdFract) == msg.sender, "Not owner");

        //get the uderlying tnft and tokenId
        ITangibleNFT _nft = _ftnft.tnft();
        uint256 _fingerprint = _ftnft.tnftFingerprint();
        uint256 fractTokenShare = _ftnft.fractionShares(_tokenIdFract);

        // get price in token for seller share
        uint256 priceFull = _sanityChecks(
            _nft,
            address(_ftnft),
            _fingerprint,
            true
        );

        uint256 priceToPay = (fractTokenShare * priceFull) / _ftnft.fullShare();
        // check whether this contract has token for liquidity
        require(IERC20(defaultToken).balanceOf(address(this)) > priceToPay);
        // transfer NFT to this contract
        _ftnft.safeTransferFrom(msg.sender, address(this), _tokenIdFract);
        // transfer token to seller
        IERC20(defaultToken).safeTransfer(msg.sender, priceToPay);

        // make a sale here set instantmarketplace.
        instantMarketplace[address(_ftnft)][_tokenIdFract] = InstantLot(
            address(_ftnft),
            _tokenIdFract,
            address(this),
            true
        );
        //update tracker
        updateTrackerFtnft(_ftnft, _tokenIdFract, true);
    }

    function buyFractionInstant(
        ITangibleFractionsNFT _ftnft,
        uint256 _tokenFractId
    ) external override {
        require(instantAllowed, "Trading stopped");
        require(
            (instantAllowedTimestamp + 1 hours) < block.timestamp,
            "One hr not passed"
        );
        require(
            instantMarketplace[address(_ftnft)][_tokenFractId].nft !=
                address(0),
            "No lot"
        );

        //get the uderlying tnft and tokenId
        ITangibleNFT _nft = _ftnft.tnft();
        uint256 _fingerprint = _ftnft.tnftFingerprint();
        uint256 fractTokenShare = _ftnft.fractionShares(_tokenFractId);

        uint256 priceFull = _sanityChecks(
            _nft,
            address(_ftnft),
            _fingerprint,
            false
        );
        uint256 priceToTake = (fractTokenShare * priceFull) /
            _ftnft.fullShare();
        //take token
        IERC20(defaultToken).safeTransferFrom(
            msg.sender,
            address(this),
            priceToTake
        );
        //send the nft to buyer
        IERC721(_ftnft).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenFractId
        );

        delete instantMarketplace[address(_ftnft)][_tokenFractId];
        //update tracker
        updateTrackerFtnft(_ftnft, _tokenFractId, false);
    }

    // USDC-TNGBL oracle
    function _getUSDCToTNGBL(uint256 _amount) internal view returns (uint256) {
        address usdc = address(IFactory(factory).USDC());
        address tngbl = address(IFactory(factory).TNGBL());

        uint256 tngblValue = tngblOracle.consult(usdc, _amount, tngbl);

        return tngblValue;
    }

    function _volatilityCheck() internal {
        address usdc = address(IFactory(factory).USDC());
        address tngbl = address(IFactory(factory).TNGBL());

        tngblOracle.update(tngbl, usdc);
        uint256 tngblOraclePrice = tngblOracle.consult(tngbl, 1e18, usdc);

        // to do comparison for volatility
        uint256 tngblSushiPrice = exchange.quoteOut(tngbl, usdc, 1e18);
        // protection against high volatility
        require(
            IILCalculator(instantCalculator).isItVolatile(
                tngblOraclePrice,
                tngblSushiPrice
            ),
            "Too volatile"
        );
    }

    function withdrawUSDC() external override onlyFactoryAdmin {
        IERC20 usdc = IFactory(factory).USDC();
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
    }

    function withdrawToken(IERC20 token) external onlyFactoryAdmin {
        token.transfer(msg.sender, token.balanceOf(address(this)));
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
                ? IFactory(factory)
                    .priceManager()
                    .getPriceOracleForCategory(nft)
                    .usdcPrice(nft, paymentUSDToken, data, 0)
                : IFactory(factory)
                    .priceManager()
                    .getPriceOracleForCategory(nft)
                    .usdcPrice(nft, paymentUSDToken, 0, data);
    }

    function withdrawTNGBL() external override onlyFactoryAdmin {
        IERC20 tngbl = IFactory(factory).TNGBL();
        tngbl.transfer(msg.sender, tngbl.balanceOf(address(this)));
    }

    function withdrawTnft(ITangibleNFT _nft, uint256 _tokenId)
        external
        onlyFactoryAdmin
    {
        require(_nft.ownerOf(_tokenId) == address(this), "IL not owner");
        _nft.safeTransferFrom(address(this), msg.sender, _tokenId);
        delete instantMarketplace[address(_nft)][_tokenId];
    }

    function withdrawFTnft(ITangibleFractionsNFT _ftnft, uint256 _tokenId)
        external
        onlyFactoryAdmin
    {
        require(_ftnft.ownerOf(_tokenId) == address(this), "IL not fowner");
        _ftnft.safeTransferFrom(address(this), msg.sender, _tokenId);
        delete instantMarketplace[address(_ftnft)][_tokenId];
    }

    function onERC721Received(
        address operator,
        address seller,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return _onERC721Received(operator, seller, tokenId, data);
    }

    function _onERC721Received(
        address, /*operator*/
        address, /*seller*/
        uint256, /*tokenId*/
        bytes calldata /*data*/
    ) private pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
