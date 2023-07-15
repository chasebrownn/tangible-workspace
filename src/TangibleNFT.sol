// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./interfaces/ITangibleNFT.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IOwnable.sol";
import "./abstract/AdminAccess.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TangibleNFT is
    AdminAccess,
    ERC721,
    ERC721Enumerable,
    ERC721Pausable,
    ITangibleNFT,
    IERC721Receiver
{
    using SafeERC20 for IERC20;
    using Strings for uint256;

    //for rent
    bytes32 public constant SHARE_MANAGER_ROLE = keccak256("SHARE_MANAGER");
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");

    mapping(uint256 => uint256) public override storageEndTime;
    //new info in v2
    //eg 1 -> 'someuniquestring'
    mapping(uint256 => string) public override fingerprintToProductId;
    //eg 0x01000001 -> 3
    mapping(uint256 => uint256) public override tokensFingerprint;
    mapping(uint256 => address) public rentRevenueShare;
    string[] private productIds;
    uint256[] public fingeprintsInTnft;
    //starting point for tnfts
    uint256 private _lastTokenId = 0x0100000000000000000000000000000000;
    mapping(uint256 => address) private _originalTokenOwners;

    mapping(uint256 => bool) public override blackListedTokens;

    //status mappings
    mapping(uint256 => bool) public tnftCustody;

    // lockpercentage is 100% - 10000 50% - 5000
    uint256 public override lockPercent;
    bool public immutable override paysRent;
    uint256 public override storagePricePerYear;
    uint256 public override storagePercentagePricePerYear; //max percent precision is 2 decimals 100% is 10000 0.01% is 1
    bool public override storagePriceFixed;
    bool public override storageRequired;
    address public factory;
    uint256 public immutable deploymentBlock;

    //passive income nfts book keeping
    mapping(uint256 => uint256) public override tnftToPassiveNft;

    string private _baseUriLink;

    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }

    constructor(
        address _factory,
        string memory category,
        string memory symbol,
        string memory uri,
        bool _storagePriceFixed,
        bool _storageRequired,
        uint256 _lockPercentage,
        bool _paysRent
    ) ERC721(category, symbol) {
        require(_factory != address(0), "FZ");
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, _factory);

        factory = _factory;
        _baseUriLink = uri;

        storagePriceFixed = _storagePriceFixed;
        storagePricePerYear = 20000000; // 20$ in USDC
        storagePercentagePricePerYear = 100; //1 percent
        storageRequired = _storageRequired;
        lockPercent = _lockPercentage;
        paysRent = _paysRent;

        deploymentBlock = block.number;
    }

    function baseSymbolURI() external view override returns (string memory) {
        return string(abi.encodePacked(_baseUriLink, "/", symbol(), "/"));
    }

    function setBaseURI(string calldata uri) external onlyFactoryAdmin {
        _baseUriLink = uri;
    }

    function setFactory(address _factory) external onlyFactoryAdmin {
        factory = _factory;
    }

    function _roleGranter(
        address granter,
        address to,
        bytes32 roleToGrant
    ) internal {
        AccessControl(granter).grantRole(roleToGrant, to);
    }

    function togglePause() external onlyFactoryAdmin {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, IERC721Metadata)
        returns (string memory)
    {
        return
            bytes(_baseUriLink).length > 0
                ? string(
                    abi.encodePacked(
                        _baseUriLink,
                        "/",
                        symbol(),
                        "/",
                        tokenId.toString()
                    )
                )
                : "";
    }

    function isApprovedForAll(address account, address operator)
        public
        view
        override(ERC721, IERC721)
        returns (bool)
    {
        return
            operator == factory || ERC721.isApprovedForAll(account, operator);
    }

    /// @inheritdoc ITangibleNFT
    function produceMultipleTNFTtoStock(
        uint256 count,
        uint256 fingerprint,
        address toStock
    ) external override onlyFactory returns (uint256[] memory) {
        require(bytes(fingerprintToProductId[fingerprint]).length > 0, "FNA");
        uint256[] memory mintedTnfts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            mintedTnfts[i] = _produceTNFTtoStock(toStock, fingerprint);
        }
        emit ProducedTNFTs(mintedTnfts);
        return mintedTnfts;
    }

    function _produceTNFTtoStock(address toStock, uint256 fingerprint)
        internal
        returns (uint256)
    {
        uint256 tokenToMint = ++_lastTokenId;

        //create new tnft and update last produced tnft in map
        _mint(toStock, tokenToMint);
        if (paysRent) {
            RevenueShare rentRevenueShare_ = IFactory(factory)
                .rentShare()
                .forToken(address(this), tokenToMint);
            rentRevenueShare[tokenToMint] = address(rentRevenueShare_);

            _roleGranter(
                address(rentRevenueShare_),
                address(this),
                SHARE_MANAGER_ROLE
            );

            _roleGranter(
                address(rentRevenueShare_),
                address(this),
                CLAIMER_ROLE
            );

            rentRevenueShare_.updateShare(address(this), tokenToMint, 1e18);
        }
        //store fingerprint to token id
        tokensFingerprint[tokenToMint] = fingerprint;
        _originalTokenOwners[tokenToMint] = toStock;
        tnftCustody[tokenToMint] = true;
        return tokenToMint;
    }

    function lockTNGBL(
        uint256 tokenId,
        uint256 _years,
        uint256 lockedAmount,
        bool onlyLock
    ) external override onlyFactory {
        //approve immediatelly speinding of TNGBL token in favor of
        //passive incomeNFT contract
        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();
        IFactory(factory).TNGBL().approve(address(piNft), lockedAmount);
        //handle passive income minting
        uint8 toLock = uint8(12 * _years);
        if (toLock > piNft.maxLockDuration()) {
            toLock = piNft.maxLockDuration();
        }
        uint256 passiveTokenId = piNft.mint(
            address(this),
            lockedAmount,
            toLock,
            onlyLock,
            false
        );
        tnftToPassiveNft[tokenId] = passiveTokenId;

        PassiveIncomeNFT.Lock memory lock = piNft.locks(
            tnftToPassiveNft[tokenId]
        );
        _updateRevenueShare(
            address(this),
            tokenId,
            int256(lock.lockedAmount + lock.maxPayout)
        );
    }

    function setRolesForFraction(address ftnft, uint256 tnftTokenId)
        external
        override
        onlyFactory
    {
        RevenueShare rentRevenueShare_ = IFactory(factory).rentShare().forToken(
            address(this),
            tnftTokenId
        );
        _roleGranter(address(rentRevenueShare_), ftnft, SHARE_MANAGER_ROLE);

        _roleGranter(address(rentRevenueShare_), ftnft, CLAIMER_ROLE);
    }

    function burn(uint256 tokenId) external onlyFactoryAdmin {
        require(msg.sender == ownerOf(tokenId), "NOW");
        _setTNFTStatus(tokenId, false);
        _burn(tokenId);
    }

    function claim(uint256 tokenId, uint256 amount) external override {
        require(ownerOf(tokenId) == msg.sender, "NOOT");
        PassiveIncomeNFT piNft = IFactory(factory).passiveNft();
        (uint256 free, ) = piNft.claimableIncome(tnftToPassiveNft[tokenId]);
        piNft.claim(tnftToPassiveNft[tokenId], amount);
        IFactory(factory).TNGBL().safeTransfer(msg.sender, amount);
        if (amount > free) {
            PassiveIncomeNFT.Lock memory lock = piNft.locks(
                tnftToPassiveNft[tokenId]
            );
            _updateRevenueShare(
                address(this),
                tokenId,
                int256(lock.lockedAmount + lock.maxPayout)
            );
        }
    }

    //passive income logic end

    /// @inheritdoc ITangibleNFT
    function setTNFTStatuses(
        uint256[] calldata tokenIds,
        bool[] calldata inOurCustody
    ) external override onlyFactory {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            _setTNFTStatus(tokenIds[i], inOurCustody[i]);
        }
    }

    function _setTNFTStatus(uint256 tokenId, bool inOurCustody) internal {
        tnftCustody[tokenId] = inOurCustody;
        //this should execute only once
        if (tnftToPassiveNft[tokenId] != 0 && !inOurCustody) {
            PassiveIncomeNFT piNft = IFactory(factory).passiveNft();
            IERC721(address(piNft)).safeTransferFrom(
                address(this),
                ownerOf(tokenId), //send it to the owner of TNFT
                tnftToPassiveNft[tokenId]
            );
            PassiveIncomeNFT.Lock memory lock = piNft.locks(
                tnftToPassiveNft[tokenId]
            );
            _updateRevenueShare(
                address(this),
                tokenId,
                -int256(lock.lockedAmount + lock.maxPayout)
            );
            _updateRevenueShare(
                address(piNft),
                tnftToPassiveNft[tokenId],
                int256(lock.lockedAmount + lock.maxPayout)
            );

            piNft.setGenerateRevenue(tnftToPassiveNft[tokenId], true);
            delete tnftToPassiveNft[tokenId];
        }
    }

    function _updateRevenueShare(
        address contractAddress,
        uint256 tokenId,
        int256 value
    ) internal {
        IFactory(factory).revenueShare().updateShare(
            contractAddress,
            tokenId,
            value
        );
    }

    /// @inheritdoc ITangibleNFT
    function isStorageFeePaid(uint256 tokenId)
        public
        view
        override
        returns (bool)
    {
        return _isStorageFeePaid(tokenId);
    }

    function _isStorageFeePaid(uint256 tokenId) internal view returns (bool) {
        return storageEndTime[tokenId] > block.timestamp;
    }

    function setStoragePricePerYear(uint256 _storagePricePerYear)
        external
        onlyFactoryAdmin
    {
        // price should be higher than 1$ at least in usdc
        require(_storagePricePerYear >= 1000000, "SPL");
        if (storagePricePerYear != _storagePricePerYear) {
            emit StoragePricePerYearSet(
                storagePricePerYear,
                _storagePricePerYear
            );
            storagePricePerYear = _storagePricePerYear;
        }
    }

    function setStoragePercentPricePerYear(
        uint256 _storagePercentagePricePerYear
    ) external onlyFactoryAdmin {
        // price should be higher than 0.5% at least in usdc
        require(_storagePercentagePricePerYear >= 50, "SPRL");
        if (storagePercentagePricePerYear != _storagePercentagePricePerYear) {
            emit StoragePercentagePricePerYearSet(
                storagePricePerYear,
                _storagePercentagePricePerYear
            );
            storagePercentagePricePerYear = _storagePercentagePricePerYear;
        }
    }

    /// @inheritdoc ITangibleNFT
    function adjustStorageAndGetAmount(
        uint256 tokenId,
        uint256 _years,
        uint256 tokenPrice
    ) external override onlyFactory returns (uint256) {
        uint256 lastPaidDate = storageEndTime[tokenId];
        if (lastPaidDate == 0) {
            lastPaidDate = block.timestamp;
        }
        //calculate to which point storage will last
        lastPaidDate += _years * 365 days;
        storageEndTime[tokenId] = lastPaidDate;

        //amount in usdc to pay
        uint256 amount;
        if (storagePriceFixed) {
            amount = storagePricePerYear * _years;
        } else {
            require(tokenPrice > 0, "Price 0");
            amount =
                (tokenPrice * storagePercentagePricePerYear * _years) /
                10000;
        }

        emit StorageFeeToPay(tokenId, _years, amount);

        return amount;
    }

    function toggleStorageFee(bool value) external onlyFactoryAdmin {
        storagePriceFixed = value;
    }

    function toggleStorageRequired(bool value) external onlyFactoryAdmin {
        storageRequired = value;
    }

    function addFingerprintsIds(
        uint256[] calldata fingerprints,
        string[] calldata ids
    ) external onlyFactoryAdmin {
        require(
            fingerprints.length == ids.length,
            "ANL" //array lengths not same
        );
        require(fingerprints.length > 0, "AE"); //array must not be empty
        uint256 lengthArray = fingerprints.length;
        uint256 i = 0;
        while (i < lengthArray) {
            require(
                bytes(fingerprintToProductId[fingerprints[i]]).length == 0,
                "FAA"
            );
            fingerprintToProductId[fingerprints[i]] = ids[i];
            //use this to return all ids
            productIds.push(ids[i]);
            fingeprintsInTnft.push(fingerprints[i]);
            i++;
        }
    }

    function setTnftPercentage(uint16 percent) external onlyFactoryAdmin {
        require(((percent >= 5) && (percent <= 10000)), "POR");
        lockPercent = percent;
    }

    function tnftToPassiveNftBatch(uint256[] calldata tnfts)
        public
        view
        returns (uint256[] memory passiveNfts)
    {
        uint256 length = tnfts.length;
        passiveNfts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            passiveNfts[i] = tnftToPassiveNft[tnfts[i]];
        }

        return passiveNfts;
    }

    function getFingerprintsAndProductIds()
        public
        view
        returns (uint256[] memory, string[] memory)
    {
        return (fingeprintsInTnft, productIds);
    }

    function blacklistToken(uint256 tokenId, bool blacklisted)
        external
        onlyFactoryAdmin
    {
        blackListedTokens[tokenId] = blacklisted;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC721, ERC721Enumerable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _isTokenMinter(address from, uint256 tokenId)
        internal
        view
        returns (bool)
    {
        if (_originalTokenOwners[tokenId] == from) {
            return true;
        }
        return false;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, tokenId);
        // Allow operations if admin, factory or 0 address
        if (
            IFactory(factory).isFactoryAdmin(from) ||
            (factory == from) ||
            from == address(0) ||
            to == address(0)
        ) {
            return;
        }

        // we prevent transfers if blacklisted or not in our custody(redeemed)
        if (blackListedTokens[tokenId] || !tnftCustody[tokenId]) {
            revert("BL");
        }
        // for houses there is no storage so just allow transfer
        if (!storageRequired) {
            return;
        }
        if (!_isStorageFeePaid(tokenId) && !_isTokenMinter(from, tokenId)) {
            revert("CT");
        }
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
