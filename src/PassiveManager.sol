// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { AdminAccess } from "./abstract/AdminAccess.sol";
import { IFactory, PassiveIncomeNFT, RevenueShare } from "./interfaces/IFactory.sol";
import { IPassiveManager } from "./IPassiveManager.sol";
import { IRevisedTNFT } from "./IRevisedTNFT.sol";

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

    /// @notice A mapping from TNFT contract address to tokenId to amount rewards claimed.
    mapping(address => mapping(uint256 => uint256)) public passiveClaimed;

    /// @notice Used to store the contract address of Factory.sol.
    address public immutable factory;

    /// @notice Used to store the address of revenueShareContract.
    RevenueShare public immutable revenueShareContract;


    // ~ Constructor ~

    /// @notice Initialize contract.
    /// @param _factory address of Factory contract.
    constructor(
        address _factory
    ) {
        _grantRole(FACTORY_ROLE, _factory);
        factory = _factory;

        revenueShareContract = IFactory(_factory).revenueShare();
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

    /// @notice This function allows for locking of TNBGL tokens for a passiveIncome NFT.
    /// @dev Only callable by Factory.
    /// @param _contract TNGBL contract address.
    /// @param tokenId tokenId allowing you to lock your TNGBL tokens.
    /// @param _years amount of time to lock TNGBL tokens. Will be multiplied by 12 months.
    /// @param lockedAmount Amount of TNGBL to lock.
    /// @param onlyLock If true, TNGBL will lock with no rewards. If false, owner will be eligible for rewards.
    function lockTNGBL(address _contract, uint256 tokenId, uint256 _years, uint256 lockedAmount, bool onlyLock) external override onlyFactory {
        require(registered[_contract], "PassiveManager.sol::lockTNGBL() contract provided is not registered");

        // Grab piNft address from Factory.
        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();

        // Approve spend of TNGBL from PassiveManager to wherever piNft specifies when calling transferFrom()
        IFactory(factory).TNGBL().approve(address(piNft), lockedAmount);

        // toLock -> time to lock TNGBL in months.
        uint8 toLock = uint8(12 * _years);
        if (toLock > piNft.maxLockDuration()) {
            toLock = piNft.maxLockDuration();
        }

        // mint passive nft and update lock data on the piNft contract. Nft will mint directly to the TNFT contract.
        uint256 passiveTokenId = piNft.mint(_contract, lockedAmount, toLock, onlyLock, false);
        tnftToPassiveNft[_contract][tokenId] = passiveTokenId;

        // Fetch lock data for this lock instance.
        PassiveIncomeNFT.Lock memory lock = piNft.locks(tnftToPassiveNft[_contract][tokenId]);
        _updateRevenueShare(_contract, tokenId, int256(lock.lockedAmount + lock.maxPayout));
    }

    /// @notice This function allows a pi owner to receive rewards.
    /// @param _contract TNFT contract address.
    /// @param tokenId token identifier.
    /// @param amount amount of rewards to claim.
    function claim(address _contract, uint256 tokenId, uint256 amount) external override {
        uint256 share = IRevisedTNFT(_contract).balanceOf(msg.sender, tokenId);
        require(share > 0, "PassiveManager.sol::lockTNGBL() insufficient balance");

        // Grab piNft address from Factory.
        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();

        // Use piNft.claimableIncome() to fetch the amount that the user is eligible for in terms of passive income, if any at all.
        (uint256 free, ) = piNft.claimableIncome(tnftToPassiveNft[_contract][tokenId]);

        // Use piNft.claim() to initiate a transfer of tokens from piNft to address(this).
        piNft.claim(tnftToPassiveNft[_contract][tokenId], amount);

        // Fetch lock instance for this tokenId and calculate total rewards claimable.
        PassiveIncomeNFT.Lock memory lock = piNft.locks(tnftToPassiveNft[_contract][tokenId]);
        uint256 totalClaimable = free + lock.claimed;

        // Calculate amount in event ownership is shared
        uint256 fractionalClaimable = (totalClaimable * share) / IRevisedTNFT(_contract).getMaxBal();
        amount = fractionalClaimable - passiveClaimed[_contract][tokenId];

        // Address(this) now transfers TNGBL from this contract to the msg.sender.
        IFactory(factory).TNGBL().safeTransfer(msg.sender, amount);
        passiveClaimed[_contract][tokenId] += amount;

        // If amount > free, the base rev share is penalized so we update the Factory rev share state.
        if (amount > free) {
            _updateRevenueShare(_contract, tokenId, int256(lock.lockedAmount + lock.maxPayout));
        }
    }

    /// @notice This function migrates a piNft from this contract to a TNFT owner.
    /// @param tokenId token identifier.
    /// @param owner address of TNFT owner. Recipient of rewards.
    function movePassiveNftToOwner(uint256 tokenId, address owner) external {
        address caller = msg.sender;
        require(registered[caller], "PassiveManager.sol::deletePassiveNft() caller is not registered");

        // Grab piNft address from Factory.
        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();

        // Transfer piNft from this contract to the TNFT owner.
        IERC721(address(piNft)).safeTransferFrom(address(this), owner, tnftToPassiveNft[caller][tokenId]);

        // Fetch lock data for this lock instance.
        PassiveIncomeNFT.Lock memory lock = piNft.locks(tnftToPassiveNft[caller][tokenId]);
        
        // Update rev share eligibility amount for this contract.
        _updateRevenueShare(address(this), tokenId, -int256(lock.lockedAmount + lock.maxPayout));

        // Update rev share eligibility amount for the piNft contract.
        _updateRevenueShare(address(piNft), tnftToPassiveNft[caller][tokenId], int256(lock.lockedAmount + lock.maxPayout));

        piNft.setGenerateRevenue(tnftToPassiveNft[caller][tokenId], true);
        delete tnftToPassiveNft[caller][tokenId];
    }

    /// @notice This function is called to claim passive rewards.
    /// @param _contract TNFT contract address.
    /// @param tokenId token identifier.
    function claimForTokenExternal(address _contract, uint256 tokenId) external {
        require(registered[_contract], "PassiveManager.sol::claimForTokenExternal() caller is not registered");
        revenueShareContract.claimForToken(_contract, tokenId);
    }


    // ~ Internal Functions ~

    /// @notice Internal function to update revShare on the revenue share contract.
    /// @param contractAddress contract address.
    /// @param tokenId token identifier.
    /// @param value amount rev share.
    function _updateRevenueShare(address contractAddress, uint256 tokenId, int256 value) internal {
        IFactory(factory).revenueShare().updateShare(contractAddress, tokenId, value);
    }


    // ~ View Functions ~

    //

}