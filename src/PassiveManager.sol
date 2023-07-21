// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { AdminAccess } from "./abstract/AdminAccess.sol";
import { IFactory, PassiveIncomeNFT } from "./interfaces/IFactory.sol";
import { IPassiveManager } from "./IPassiveManager.sol";

import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice PassiveManager is used to facilitate the claiming of TNGBL passive income.
contract PassiveManager is AdminAccess, IPassiveManager {
    using SafeERC20 for IERC20;

    // ~ State Variabls ~

    /// @notice A mapping from TNFT contract address to bool. If true, contract may reference the StorageManager.
    mapping(address => bool) public override registered;

    /// @notice A mapping from TNFT contract address to tokenId to passiveTokenId.
    mapping(address => mapping(uint256 => uint256)) public tnftToPassiveNft;

    /// @notice Used to store the contract address of Factory.sol.
    address public immutable factory;


    // ~ Constructor ~

    /// @notice Initialize contract.
    /// @param _factory address of Factory contract.
    constructor(
        address _factory
    ) {
        _grantRole(FACTORY_ROLE, _factory);
        factory = _factory;
    }


    // ~ Modifiers ~

    /// @notice Modifier for verifying msg.sender to be the Factory admin.
    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }


    // ~ External Functions ~

    /// @notice This function sets a contract to bool value in registered mapping.
    /// @dev Should be called after TNFT contract is deployed if passive income is required. Callable by Factory.
    /// @param _contract TNFT contract address that should be registered.
    /// @param _eligibleForPassive If true, needs to be registered and eligible for passive NFTs.
    function registerWithPassiveManager(address _contract, bool _eligibleForPassive) external override onlyFactory {
        registered[_contract] = _eligibleForPassive;
    }

    // TODO: TEST
    function lockTNGBL(address _contract, uint256 tokenId, uint256 _years, uint256 lockedAmount, bool onlyLock) external override onlyFactory {
        require(registered[_contract], "PassiveManager.sol::lockTNGBL() contract provided is not registered");
        //approve immediatelly spending of TNGBL token in favor of
        //passive incomeNFT contract
        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();
        IFactory(factory).TNGBL().approve(address(piNft), lockedAmount); // approve spend 
        //handle passive income minting
        uint8 toLock = uint8(12 * _years);
        if (toLock > piNft.maxLockDuration()) {
            toLock = piNft.maxLockDuration();
        }
        uint256 passiveTokenId = piNft.mint(_contract, lockedAmount, toLock, onlyLock, false); // mint passive nft given lock time and amount of $TNGBL
        tnftToPassiveNft[_contract][tokenId] = passiveTokenId; // set passive nft tokenId in mapping

        PassiveIncomeNFT.Lock memory lock = piNft.locks(tnftToPassiveNft[_contract][tokenId]); 
        _updateRevenueShare(_contract, tokenId, int256(lock.lockedAmount + lock.maxPayout));
    }

    // TODO: TEST
    function claim(address _contract, uint256 tokenId, uint256 amount) external override {
        require(IERC1155(_contract).balanceOf(msg.sender, tokenId) > 0, "PassiveManager.sol::lockTNGBL() insufficient balance");

        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();
        (uint256 free, ) = piNft.claimableIncome(tnftToPassiveNft[_contract][tokenId]);

        piNft.claim(tnftToPassiveNft[_contract][tokenId], amount);
        IFactory(factory).TNGBL().safeTransfer(msg.sender, amount);

        if (amount > free) {
            PassiveIncomeNFT.Lock memory lock = piNft.locks(tnftToPassiveNft[_contract][tokenId]);
            _updateRevenueShare(_contract, tokenId, int256(lock.lockedAmount + lock.maxPayout));
        }
    }

    // TODO: Test
    function deletePassiveNft(uint256 tokenId, address owner) external {
        address caller = msg.sender;
        require(registered[caller], "PassiveManager.sol::deletePassiveNft() caller is not registered");

        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();
        IERC721(address(piNft)).safeTransferFrom(
            address(this),
            owner, //send it to the owner of TNFT
            tnftToPassiveNft[caller][tokenId]
        );
        PassiveIncomeNFT.Lock memory lock = piNft.locks(
            tnftToPassiveNft[caller][tokenId]
        );
        _updateRevenueShare(
            address(this),
            tokenId,
            -int256(lock.lockedAmount + lock.maxPayout)
        );
        _updateRevenueShare(
            address(piNft),
            tnftToPassiveNft[caller][tokenId],
            int256(lock.lockedAmount + lock.maxPayout)
        );

        piNft.setGenerateRevenue(tnftToPassiveNft[caller][tokenId], true);
        delete tnftToPassiveNft[caller][tokenId];
    }


    // ~ Internal Functions ~

    /// @notice Internal function to update revShare on the revenue share contract.
    /// @param contractAddress contract address.
    /// @param tokenId token identifier.
    /// @param value TODO
    function _updateRevenueShare(address contractAddress, uint256 tokenId, int256 value) internal {
        IFactory(factory).revenueShare().updateShare(contractAddress, tokenId, value);
    }


    // ~ View Functions ~

    //

}