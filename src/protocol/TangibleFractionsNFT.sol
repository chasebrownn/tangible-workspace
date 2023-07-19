// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../helpers/RevenueShareTransfer.sol";
import "../interfaces/ITangibleFractionsNFT.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IOwnable.sol";
import "../interfaces/IInitialReSeller.sol";
import "../interfaces/IFractionStorageManager.sol";
import "../abstract/AdminAccess.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IFactoryExt is IFactory {
    function fractionToTnftAndId(ITangibleFractionsNFT fraction)
        external
        view
        returns (TnftWithId memory);
}

interface IInitialReSellerExt is IInitialReSeller {
    function saleData(ITangibleFractionsNFT ftnft)
        external
        view
        returns (FractionSaleData memory);
}

contract TangibleFractionsNFT is
    ERC721,
    ERC721Enumerable,
    IERC721Receiver,
    ITangibleFractionsNFT,
    AccessControl
{
    event Claim(
        address indexed account,
        uint256 indexed fractionId,
        uint256 value
    );
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY");

    using SafeERC20 for IERC20;
    using Strings for uint256;
    using RevenueShareTransfer for RevenueShare;

    string private _tnftProductId;

    bool private immutable _updateRevenueShare;
    bool private immutable _updateRentShare;

    RevenueShare public immutable revenueShare;
    RevenueShare public immutable rentShare;

    ITangibleNFT public immutable override tnft;
    IFractionStorageManager public immutable storageManager;
    uint256 public immutable override tnftTokenId;
    uint256 public immutable override tnftFingerprint;
    uint256 public immutable passiveTokenId;
    uint256 public immutable deploymentBlock;
    uint256 public immutable override fullShare = 10000000; //number which represents 100% sets via constructor. 100 000 for example that supports 0.001

    address public immutable originalTnftOwner;
    //tokenId -> share precentage in relation to fullShare. 40% is 40000 of 100000. precission is 3 decimals
    mapping(uint256 => uint256) public override fractionShares;

    uint256 private _tokenIds;

    IFactoryExt public factory;

    mapping(uint256 => uint256) public claimed; // fractionId => claimed amount

    modifier onlyFactoryAdmin() {
        require(factory.isFactoryAdmin(msg.sender), "NFA");
        _;
    }

    modifier onlyFactory() {
        require(hasRole(FACTORY_ROLE, msg.sender), "NFAC");
        _;
    }

    constructor(
        address _factory,
        address _tnft,
        address _storageManager,
        string memory _fractName,
        string memory _fractSymbol,
        uint256 _tokenIdToFract,
        address rentShare_
    ) ERC721(_fractName, _fractSymbol) {
        require(_factory != address(0), "FZ");
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        factory = IFactoryExt(_factory);

        tnft = ITangibleNFT(_tnft);
        ITangibleNFT tempTnft = ITangibleNFT(_tnft);
        tnftTokenId = _tokenIdToFract;
        uint256 fingerPrint = tempTnft.tokensFingerprint(_tokenIdToFract);
        tnftFingerprint = fingerPrint;
        passiveTokenId = tempTnft.tnftToPassiveNft(_tokenIdToFract);
        _tnftProductId = tempTnft.fingerprintToProductId(fingerPrint);
        originalTnftOwner = tempTnft.ownerOf(_tokenIdToFract);
        storageManager = IFractionStorageManager(_storageManager);

        deploymentBlock = block.number;

        revenueShare = IFactory(_factory).revenueShare();
        rentShare = RevenueShare(rentShare_);

        _updateRevenueShare = tempTnft.tnftToPassiveNft(_tokenIdToFract) != 0;
        _updateRentShare = rentShare_ != address(0);
    }

    function baseURI() public view returns (string memory) {
        return tnft.tokenURI(tnftTokenId);
    }

    function setFactory(address _factory) external onlyFactoryAdmin {
        factory = IFactoryExt(_factory);
    }

    function claim(uint256 fractionId, uint256 amount) external {
        require(msg.sender == ownerOf(fractionId), "NOW");
        uint256 free = claimableIncome(fractionId);
        require(amount <= free, "AEI");
        _claimTngbl(msg.sender, fractionId, amount);
    }

    function _claimTngbl(
        address sender,
        uint256 fractionId,
        uint256 amount
    ) internal {
        if (passiveTokenId != 0) {
            //it means there is something to claim
            claimed[fractionId] += amount;
            tnft.claim(tnftTokenId, amount);
            factory.TNGBL().safeTransfer(sender, amount);
            emit Claim(sender, fractionId, amount);
        }
    }

    function claimableIncome(uint256 fractionId) public view returns (uint256) {
        PassiveIncomeNFT piNft = factory.passiveNft();
        (uint256 free, ) = piNft.claimableIncome(passiveTokenId);
        PassiveIncomeNFT.Lock memory lock = piNft.locks(passiveTokenId);
        uint256 totalClaimable = free + lock.claimed;
        uint256 fractionalClaimable = (totalClaimable *
            fractionShares[fractionId]) / fullShare;
        return fractionalClaimable - claimed[fractionId];
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, IERC721Metadata)
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    tnft.tokenURI(tnftTokenId),
                    "/fraction/",
                    tokenId.toString()
                )
            );
    }

    function _mintFtnft(
        address to,
        uint256 tokenId,
        uint256 revenueShare_,
        uint256 rentShare_
    ) internal {
        _safeMint(to, tokenId, abi.encode(0, true));
        _mintShareHelper(tokenId, revenueShare_, rentShare_);
    }

    function _mintShareHelper(
        uint256 tokenId,
        uint256 revenueShare_,
        uint256 rentShare_
    ) internal {
        revenueShare.mintShare(
            _updateRevenueShare,
            address(this),
            tokenId,
            revenueShare_
        );
        rentShare.mintShare(
            _updateRentShare,
            address(this),
            tokenId,
            rentShare_
        );
    }

    function _burnShareHelper(address who, uint256 tokenId) internal returns (uint256 revShare) {

        revShare = revenueShare.burnShare(_updateRevenueShare, who, tokenId);
        rentShare.burnShare(_updateRentShare, who, tokenId);
    }

    function _claim(address contractAddress, uint256 tokenId) internal {
        if (_updateRevenueShare) {
            revenueShare.claimForToken(contractAddress, tokenId);
        }
        if (_updateRentShare) {
            rentShare.claimForToken(contractAddress, tokenId);
        }
    }

    function claimFor(address contractAddress, uint256 tokenId) external override onlyFactory {
        //claim rent, revenue
        _claim(contractAddress, tokenId);
        //claim tngbl
        _claimTngbl(ownerOf(tokenId), tokenId, claimableIncome(tokenId));
    }

    /// @notice takes the original TNFT and breaks it into new fraction TNFTs
    function initialSplit(address owner, address _tnft, uint256 _tnftTokenId, uint256 keepShare, uint256 sellShare) external override onlyFactory returns (uint256 tokenKeep, uint256 tokenSell) {
        require((address(tnft) == _tnft) && (tnftTokenId == _tnftTokenId), "WTT"); // make sure tnft and tokenID are associated with this contract
        require(((keepShare + sellShare) == fullShare) && (sellShare > 0), "SNC"); // keepShare + sellShare must == full pie. sell must be more than 0
        require(owner == tnft.ownerOf(tnftTokenId), "WO"); // owner must be the current owner of the token
        _claim(address(tnft), tnftTokenId); // auto claim passive rewards for owner

        tnft.safeTransferFrom(owner, address(this), tnftTokenId); // take the initial tnft

        uint256 revenueShare_ = _burnShareHelper(address(tnft), tnftTokenId); // TODO
    
        // keepShare = 60
        // sellShare = 40

        if (keepShare > 0) {
            //mint 1st fraction and send it to owner
            tokenKeep = ++_tokenIds;
            //set shares
            fractionShares[tokenKeep] = keepShare;
            _mintFtnft(
                owner, // owner = address(1)
                tokenKeep, // 1
                (revenueShare_ * keepShare) / fullShare, 
                (1e18 * keepShare) / fullShare
            );
        }
        //mint 2nd for sale and send it immediatelly to owner, factory will forward to marketplace
        tokenSell = ++_tokenIds;
        //set shares for sale
        fractionShares[tokenSell] = sellShare;
        _mintFtnft(
            owner,
            tokenSell,
            (revenueShare_ * sellShare) / fullShare,
            (1e18 * sellShare) / fullShare
        );
        emit ProducedInitialFTNFTs(tokenKeep, tokenSell);
    }

    struct HelperStruct {
        uint256 totalShareSum;
        uint256 totalClaimedSum;
        uint256 revenueShare_;
        uint256 rentShare_;
    }

    function fractionalize(uint256 fractionTokenId, uint256[] calldata shares) external override returns (uint256[] memory fractTokenIds) {
        uint256 length = shares.length;
        require(length >= 2, "2");
        require(ownerOf(fractionTokenId) == msg.sender, "NOW");
        // require(storageManager.canTransfer(fractionTokenId), "PS");

        _claim(address(this), fractionTokenId);

        HelperStruct memory hs;

        hs.revenueShare_ = revenueShare.totalShare(address(this));

        _burnShareHelper(address(this), fractionTokenId);
        //take memory
        fractTokenIds = new uint256[](length);
        for (uint256 i; i < length; i++) {
            require(shares[i] > 0, "Z");
            hs.totalShareSum += shares[i];
            uint256 newRevenueShare;
            uint256 newRentShare;
            unchecked {
                newRevenueShare = (hs.revenueShare_ * shares[i]) / fullShare;
                newRentShare = (1e18 * shares[i]) / fullShare;
            }
            if (i != 0) {
                //mint others
                storageManager.moveSPaymentToAnother(
                    fractionTokenId,
                    ++_tokenIds
                );
                fractionShares[_tokenIds] = shares[i];
                _mintFtnft(
                    msg.sender,
                    _tokenIds,
                    newRevenueShare,
                    newRentShare
                );
                fractTokenIds[i] = _tokenIds;
                claimed[_tokenIds] =
                    (claimed[fractionTokenId] * shares[i]) /
                    fractionShares[fractionTokenId];
                hs.totalClaimedSum += claimed[_tokenIds];
            } else {
                //update 1st token

                _mintShareHelper(
                    fractionTokenId,
                    newRevenueShare,
                    newRentShare
                );
            }
        }
        //set outside the loop of first fract, stack optimizations
        require(hs.totalShareSum == fractionShares[fractionTokenId], "wInput");
        claimed[fractionTokenId] =
            claimed[fractionTokenId] -
            hs.totalClaimedSum;
        fractionShares[fractionTokenId] = shares[0];
        fractTokenIds[0] = fractionTokenId;
        // to be safe sum, must align
        emit ProducedFTNFTs(fractTokenIds);
    }

    function defractionalize(uint256[] calldata tokenIds) external override {
        uint256 length = tokenIds.length;
        address fractsOwner = msg.sender;
        uint256 firstFract = tokenIds[0];
        uint256 transferredShare = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenIds[i]) == fractsOwner, "NOW");
            _claim(address(this), tokenId);
            if (i != 0) {
                //update 1st fraction
                uint256 tokenShare = fractionShares[tokenId];
                transferredShare += tokenShare;

                revenueShare.transferShare(
                    _updateRevenueShare,
                    address(this),
                    tokenId,
                    firstFract
                );
                rentShare.transferShare(
                    _updateRentShare,
                    address(this),
                    tokenId,
                    firstFract
                );
                //delete other fraction share and burn the token
                delete fractionShares[tokenId];
                _burn(tokenId);
                claimed[firstFract] += claimed[tokenId];
                claimed[tokenId] = 0;
            }
        }
        fractionShares[firstFract] += transferredShare;
        if (fractionShares[firstFract] == fullShare) {
            //just send the original tnft back to owner and delete this token
            revenueShare.transferShare(
                _updateRevenueShare,
                address(this),
                firstFract,
                address(tnft),
                tnftTokenId
            );
            rentShare.transferShare(
                _updateRentShare,
                address(this),
                firstFract,
                address(tnft),
                tnftTokenId
            );
            _burn(firstFract);
            claimed[firstFract] = 0;
            tnft.safeTransferFrom(address(this), fractsOwner, tnftTokenId);
            //no locked passive nft
            if (_updateRentShare) {
                rentShare.unregisterContract(address(this));
            }
            delete fractionShares[firstFract];
        }
    }

    function isApprovedForAll(address account, address operator)
        public
        view
        override(ERC721, IERC721)
        returns (bool)
    {
        return
            operator == address(factory) ||
            ERC721.isApprovedForAll(account, operator);
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        //NOTE allow us to take token if tokenId hasn't paid it's share of storage
        super._beforeTokenTransfer(from, to, tokenId);
        // Allow operations if going to
        //NOTE check if it is the first sale, only in this case we should alow marketplace
        if (
            !factory.fractionToTnftAndId(this).initialSaleDone &&
            (factory.marketplace() == from || //when marketplace sells
                (factory.marketplace() == to && from == address(0))) //when minted to marketplace
        ) {
            return;
        }
        if (
            tnft.blackListedTokens(tnftTokenId) ||
            (IInitialReSellerExt(factory.initReSeller())
                .saleData(this)
                .endTimestamp >= block.timestamp)
        ) {
            revert("TBL");
        }
        if (!storageManager.canTransfer(tokenId)) {
            //has this token paid it's share?
            revert("PS");
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
