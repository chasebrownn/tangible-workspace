// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import { RevisedTangibleNFT } from "../src/RevisedTNFT.sol";
import { Factory } from "../src/protocol/Factory.sol";


contract RevisedTNFTTest is Test {
    RevisedTangibleNFT public tNftContract;
    Factory public factory;

    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant STORAGE_ADDY = address(bytes20(bytes("Storage Address")));
    address public constant PRICE_MANAGER = address(bytes20(bytes("Price Manager")));
    address public constant FACTORY_OWNER = address(bytes20(bytes("Factory Owner")));
    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    function setUp() public {

        factory = new Factory(
            USDC,
            STORAGE_ADDY,
            PRICE_MANAGER,
            FACTORY_OWNER
        );

        tNftContract = new RevisedTangibleNFT(
            address(factory),
            "Tangible NFT",
            "TNFT",
            BASE_URI
        );

        vm.label(STORAGE_ADDY, "Storage Address");
        vm.label(PRICE_MANAGER, "Price Manager");
        vm.label(FACTORY_OWNER, "Factory Owner");
        vm.label(address(factory), "Factory Contract");
        vm.label(address(tNftContract), "Nft Contract");
    }


    // ~ Utility ~

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }


    // ~ Unit Tests ~

    function test_tangible_revisedTNFT_init_state() public {
        assertEq(tNftContract.factory(), address(factory));
        assertEq(tNftContract.category(), "Tangible NFT");
        assertEq(tNftContract.symbol(), "TNFT");
        assertEq(tNftContract.baseURI(), BASE_URI);
        assertEq(tNftContract.lastTokenId(), 0);
    }

    function test_tangible_revisedTNFT_produceMultipleTNFTtoStock_one() public {

        uint256[] memory fingerprints = new uint256[](1);
        string[] memory ids = new string[](1);

        fingerprints[0] = 42;
        ids[0] = "id_42";

        vm.prank(FACTORY_OWNER);
        tNftContract.addFingerprintsIds(fingerprints, ids);

        assertEq(tNftContract.balanceOf(address(this), 1), 0);

        vm.prank(tNftContract.factory());
        tNftContract.produceMultipleTNFTtoStock(1, 42, address(this));

        assertEq(tNftContract.balanceOf(address(this), 1), 100);
    }

}
