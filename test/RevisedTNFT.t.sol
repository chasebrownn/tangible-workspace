// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import { RevisedTangibleNFT } from "../src/RevisedTNFT.sol";
import { Factory } from "../src/protocol/Factory.sol";


// TODO: Test burn


contract RevisedTNFTTest is Test {
    RevisedTangibleNFT public tNftContract;
    Factory public factory;

    // Global constants
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant STORAGE_ADDY = address(bytes20(bytes("Storage Address")));
    address public constant PRICE_MANAGER = address(bytes20(bytes("Price Manager")));
    address public constant FACTORY_OWNER = address(bytes20(bytes("Factory Owner")));
    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    // Actors
    address public constant JOE = address(bytes20(bytes("Joe")));
    address public constant LEO = address(bytes20(bytes("Leo")));

    function setUp() public {

        // Deploy Factory
        factory = new Factory(
            USDC,
            STORAGE_ADDY,
            PRICE_MANAGER,
            FACTORY_OWNER
        );

        // Deploy RevisedTangibleNFT
        tNftContract = new RevisedTangibleNFT(
            address(factory),
            "Tangible NFT",
            "TNFT",
            BASE_URI
        );

        vm.label(STORAGE_ADDY, "Storage_Address");
        vm.label(PRICE_MANAGER, "Price_Manager");
        vm.label(FACTORY_OWNER, "Factory_Owner");
        vm.label(address(factory), "Factory_Contract");
        vm.label(address(tNftContract), "Nft_Contract");

        vm.label(JOE, "Joe_EOA");
        vm.label(LEO, "Leo_EOA");
    }


    // ~ Utility ~

    /// @notice Receipt method for single token transfers -> Allows address(this) to receive ERC1155 tokens.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice Receipt method for batch transfers -> Allows address(this) to receive ERC1155 tokens.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice Creates an instance of a fingerprint to be minted.
    function _initializeFingerprint() internal returns (uint256) {
        uint256[] memory fingerprints = new uint256[](1);
        string[] memory ids = new string[](1);

        fingerprints[0] = 42;
        ids[0] = "id_42";

        vm.prank(FACTORY_OWNER);
        tNftContract.addFingerprintsIds(fingerprints, ids);

        assertEq(tNftContract.fingerprintToProductId(42), "id_42");

        return fingerprints[0];
    }


    // ~ Unit Tests ~

    /// @notice Initial state test.
    function test_tangible_revisedTNFT_init_state() public {
        assertEq(tNftContract.factory(), address(factory));
        assertEq(tNftContract.category(), "Tangible NFT");
        assertEq(tNftContract.symbol(), "TNFT");
        assertEq(tNftContract.baseURI(), BASE_URI);
        assertEq(tNftContract.lastTokenId(), 0);
    }

    /// @notice This test verifies the functionality of safeTransferFrom.
    function test_tangible_revisedTNFT_safeTransferFrom() public {
        // set up new fingerprint to mint
        _initializeFingerprint();
        
        // Pre-state check.
        assertEq(tNftContract.balanceOf(address(JOE), 1), 0);
        assertEq(tNftContract.balanceOf(address(LEO), 1), 0);

        // factory calls produceMultipleTNFTtoStock.
        vm.prank(tNftContract.factory());
        tNftContract.produceMultipleTNFTtoStock(1, 42, address(JOE));

        // Verify Joe received his TNFT
        assertEq(tNftContract.balanceOf(address(JOE), 1), 100);
        assertEq(tNftContract.balanceOf(address(LEO), 1), 0);

        // Verify Joe cannot transfer more than sufficient balance.
        vm.prank(JOE);
        vm.expectRevert("ERC1155: insufficient balance for transfer");
        tNftContract.safeTransferFrom(JOE, LEO, 1, 101, bytes(""));

        // Joe transfer's portion of tokens to LEO -> replicating fractionalized ownership.
        vm.prank(JOE);
        tNftContract.safeTransferFrom(JOE, LEO, 1, 40, bytes(""));

        // Post-state check.
        assertEq(tNftContract.balanceOf(address(JOE), 1), 60);
        assertEq(tNftContract.balanceOf(address(LEO), 1), 40);
    }

    /// @notice This method tests the produceMultipleTNFTtoStock() function with a single token.
    function test_tangible_revisedTNFT_produceMultipleTNFTtoStock() public {
        // set up new fingerprint to mint
        uint256 fp = _initializeFingerprint();
        
        // Pre-state check.
        assertEq(tNftContract.balanceOf(address(this), 1), 0);

        // factory calls produceMultipleTNFTtoStock.
        vm.prank(tNftContract.factory());
        tNftContract.produceMultipleTNFTtoStock(1, fp, address(this));

        // Post-state check.
        assertEq(tNftContract.balanceOf(address(this), 1), 100);
        assertEq(tNftContract.tokensFingerprint(1), fp);
    }

    /// @notice This method tests the produceMultipleTNFTtoStock() function with multiple tokens of the same fingerprint.
    function test_tangible_revisedTNFT_produceMultipleTNFTtoStock_multiple() public {
        // set up new fingerprint to mint
        uint256 fp = _initializeFingerprint();

        // Pre-state check.
        assertEq(tNftContract.fingerprintToProductId(fp), "id_42");
        assertEq(tNftContract.balanceOf(address(this), 1), 0);
        assertEq(tNftContract.balanceOf(address(this), 2), 0);
        assertEq(tNftContract.balanceOf(address(this), 3), 0);
        assertEq(tNftContract.balanceOf(address(this), 4), 0);

        // factory calls produceMultipleTNFTtoStock.
        vm.prank(tNftContract.factory());
        tNftContract.produceMultipleTNFTtoStock(4, fp, address(this));

        // Post-state check.
        assertEq(tNftContract.balanceOf(address(this), 1), 100);
        assertEq(tNftContract.tokensFingerprint(1), fp);
        assertEq(tNftContract.balanceOf(address(this), 2), 100);
        assertEq(tNftContract.tokensFingerprint(2), fp);
        assertEq(tNftContract.balanceOf(address(this), 3), 100);
        assertEq(tNftContract.tokensFingerprint(3), fp);
        assertEq(tNftContract.balanceOf(address(this), 4), 100);
        assertEq(tNftContract.tokensFingerprint(4), fp);
    }

}
