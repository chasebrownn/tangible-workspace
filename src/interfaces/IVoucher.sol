// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./ITangibleNFT.sol";

interface IVoucher {
    /// @dev Voucher for lazy-minting
    struct MintVoucher {
        ITangibleNFT token;
        uint256 mintCount;
        uint256 price;
        address vendor;
        address buyer;
        uint256 fingerprint;
        bool sendToVendor;
    }

    struct MintInitialFractionVoucher {
        address seller;
        address tnft;
        uint256 tnftTokenId;
        uint256 keepShare;
        uint256 sellShare;
        uint256 sellPrice;
    }

    /// @dev Voucher for lazy-burning
    struct RedeemVoucher {
        ITangibleNFT token;
        uint256[] tokenIds;
        bool[] inOurCustody;
    }
}
