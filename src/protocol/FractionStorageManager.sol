// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/ITangibleNFT.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/ITangibleFractionsNFT.sol";
import "../interfaces/IFractionStorageManager.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ITangiblePriceManager.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";

contract FractionStorageManager is IFractionStorageManager {
    using SafeERC20 for IERC20;
    struct StoragePaymentShare {
        bool paid;
    }

    ITangibleFractionsNFT public override fracTnft;
    ITangibleNFT public immutable tnft;
    IFactory public immutable factory;
    uint256 public immutable tnftTokenId;
    uint256 public immutable tnftFingerprint;
    uint256[] public cycles;
    uint256 public currentStorageCycle;
    //timestamp of payment => fraction tokenId to StoragePaymentShare
    //since there is no way to set all to zero after storage extension
    //this is the only way
    mapping(uint256 => mapping(uint256 => StoragePaymentShare))
        public paymentTracker;
    //timestamp -> share paid
    mapping(uint256 => uint256) public sharePaidForCycle;
    //timestamp -> price for storage in cycle
    mapping(uint256 => uint256) public storagePriceCycle;

    constructor(
        ITangibleNFT _tnft,
        IFactory _factory,
        uint256 _tnftTokenId
    ) {
        tnft = _tnft;
        tnftTokenId = _tnftTokenId;
        tnftFingerprint = _tnft.tokensFingerprint(_tnftTokenId);
        factory = _factory;
        cycles.push(_tnft.storageEndTime(_tnftTokenId));
    }

    function adjustFTNFT() external override {
        fracTnft = ITangibleFractionsNFT(factory.fractions(tnft, tnftTokenId));
        currentStorageCycle = cycles.length - 1;
    }

    //this is for users when storage is not paid to track those who paid and then fractionalize -
    // but storage is still not completely paid
    function moveSPaymentToAnother(uint256 origin, uint256 destination)
        external
        override
    {
        address sender = msg.sender;
        require(sender == address(fracTnft), "NA");
        if (_canTransfer(destination)) {
            //we don't care about shares until storage ended
            return;
        }

        paymentTracker[cycles[currentStorageCycle]][destination]
            .paid = paymentTracker[cycles[currentStorageCycle]][origin].paid;
    }

    function payShareStorage(uint256 fractTokenId) external override {
        address sender = msg.sender;
        require(sender == fracTnft.ownerOf(fractTokenId), "NOW");

        uint256 tokenShare = fracTnft.fractionShares(fractTokenId);
        if (storagePriceCycle[cycles[currentStorageCycle]] == 0) {
            //only done by first payer
            storagePriceCycle[cycles[currentStorageCycle]] = _getStoragePrice();
        }
        //calc senders share to pay
        uint256 fullShare = fracTnft.fullShare();
        uint256 totalAmount = storagePriceCycle[cycles[currentStorageCycle]];
        uint256 toPay = (tokenShare * totalAmount) / fullShare;
        //take the money
        factory.defUSD().safeTransferFrom(sender, address(this), toPay);
        //update users payment data and total share
        // paymentTracker[cycles[currentStorageCycle]][fractTokenId]
        //     .amountPaid = toPay;
        paymentTracker[cycles[currentStorageCycle]][fractTokenId].paid = true;
        //update total paid
        sharePaidForCycle[cycles[currentStorageCycle]] += tokenShare;

        //check if it is the last one to pay the share
        if (sharePaidForCycle[cycles[currentStorageCycle]] == fullShare) {
            //pay storage
            _payStorage();
        }
    }

    function _payStorage() internal {
        uint256 priceToPay = storagePriceCycle[cycles[currentStorageCycle]];
        uint256 balance = factory.defUSD().balanceOf(address(this));
        if (balance < priceToPay) {
            factory.defUSD().safeTransferFrom(
                msg.sender,
                address(this),
                (priceToPay - balance)
            );
        }

        factory.defUSD().approve(address(factory), priceToPay);
        factory.payTnftStorageWithManager(tnft, tnftTokenId, 1); //only 1 year
        //set new cycle
        cycles.push(tnft.storageEndTime(tnftTokenId));
    }

    function _getStoragePrice() internal returns (uint256) {
        if (tnft.storagePriceFixed()) {
            return tnft.storagePricePerYear();
        } else {
            (uint256 tokenPrice, , , , ) = factory
                .priceManager()
                .getPriceOracleForCategory(tnft)
                .usdcPrice(
                    tnft,
                    IERC20Metadata(address(factory.defUSD())),
                    0,
                    tnftTokenId
                );
            uint256 tokenPercentage = tnft.storagePercentagePricePerYear();
            return (tokenPercentage * tokenPrice) / 10000;
        }
    }

    function canTransfer(uint256 fractionTokenId)
        external
        view
        override
        returns (bool)
    {
        return _canTransfer(fractionTokenId);
    }

    function _canTransfer(uint256 fractionTokenId)
        internal
        view
        returns (bool)
    {
        //if storage is not required - we don't check others - real estate
        if (!tnft.storageRequired()) {
            return true;
        }
        //token blacklisted
        if (
            tnft.blackListedTokens(tnftTokenId) ||
            ERC721Pausable(address(tnft)).paused()
        ) {
            return false;
        }
        if (tnft.isStorageFeePaid(tnftTokenId)) {
            return true;
        }
        return
            paymentTracker[cycles[currentStorageCycle]][fractionTokenId].paid;
    }
}
