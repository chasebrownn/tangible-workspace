// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/IFactory.sol";

library RevenueShareTransfer {
    function burnShare(
        RevenueShare shareContract,
        bool condition,
        address contractAddress,
        uint256 tokenId
    ) internal returns (uint256) {
        if (!condition) return 0;
        return
            transferShare(
                shareContract,
                true,
                contractAddress,
                tokenId,
                address(0),
                0
            );
    }

    function mintShare(
        RevenueShare shareContract,
        bool condition,
        address contractAddress,
        uint256 tokenId,
        uint256 share
    ) internal {
        if (condition) {
            transferShare(
                shareContract,
                true,
                address(0),
                0,
                contractAddress,
                tokenId,
                share
            );
        }
    }

    function transferShare(
        RevenueShare shareContract,
        bool condition,
        address contractAddress,
        uint256 from,
        uint256 to
    ) internal returns (uint256) {
        if (!condition) return 0;
        return
            transferShare(
                shareContract,
                true,
                contractAddress,
                from,
                contractAddress,
                to
            );
    }

    function transferShare(
        RevenueShare shareContract,
        bool condition,
        address fromContractAddress,
        uint256 fromTokenId,
        address toContractAddress,
        uint256 toTokenId
    ) internal returns (uint256 share) {
        if (!condition) return 0;
        share = uint256(
            shareContract.share(
                abi.encodePacked(address(fromContractAddress), fromTokenId)
            )
        );
        transferShare(
            shareContract,
            true,
            fromContractAddress,
            fromTokenId,
            toContractAddress,
            toTokenId,
            share
        );
    }

    function transferShare(
        RevenueShare shareContract,
        bool condition,
        address fromContractAddress,
        uint256 fromTokenId,
        address toContractAddress,
        uint256 toTokenId,
        uint256 share
    ) internal {
        if (condition) {
            if (fromContractAddress != address(0)) {
                shareContract.updateShare(
                    fromContractAddress,
                    fromTokenId,
                    -int256(share)
                );
            }
            if (toContractAddress != address(0)) {
                shareContract.updateShare(
                    toContractAddress,
                    toTokenId,
                    int256(share)
                );
            }
        }
    }

    function totalShare(
        RevenueShare shareContract,
        address tokenContractAddress
    ) internal view returns (uint256 share) {
        uint256 balance = IERC721Enumerable(tokenContractAddress).totalSupply();
        for (uint256 i; i < balance; i++) {
            uint256 tokenId = IERC721Enumerable(tokenContractAddress)
                .tokenByIndex(i);
            share += uint256(
                shareContract.share(
                    abi.encodePacked(tokenContractAddress, tokenId)
                )
            );
        }
    }
}
