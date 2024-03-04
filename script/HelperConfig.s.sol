// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address vrfCoordinator;
        bytes32 gasLane;
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        uint256 deployerKey;
        address priceFeed;
        address ccipRouter;
        bytes32 donId;
    }

    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 43113) {
            activeNetworkConfig = getFujiAvaxConfig();
        } else if (block.chainid == 80001) {
            activeNetworkConfig = getPolygonMumbaiConfig();
        } else if (block.chainid == 11155420) {
            activeNetworkConfig = getSepoliaOptimismConfig();
        } else if (block.chainid == 421614) {
            activeNetworkConfig = getSepoliaArbitrumConfig();
        } else if (block.chainid == 84532) {
            activeNetworkConfig = getSepoliaBaseConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
                gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                deployerKey: vm.envUint("PRIVATE_KEY"),
                priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                ccipRouter: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
                donId: bytes32("fun-ethereum-sepolia-1")
            });
    }

    function getPolygonMumbaiConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                vrfCoordinator: 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed,
                gasLane: 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
                deployerKey: vm.envUint("PRIVATE_KEY"),
                priceFeed: 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada,
                ccipRouter: 0x1035CabC275068e0F4b745A29CEDf38E13aF41b1,
                donId: bytes32("fun-polygon-mumbai-1")
            });
    }

    function getSepoliaOptimismConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                vrfCoordinator: 0x0000000000000000000000000000000000000000,
                gasLane: 0x0,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
                deployerKey: vm.envUint("PRIVATE_KEY"),
                priceFeed: 0x61Ec26aA57019C486B10502285c5A3D4A4750AD7,
                ccipRouter: 0x114A20A10b43D4115e5aeef7345a1A71d2a60C57,
                donId: bytes32("unknown")
            });
    }

    function getSepoliaArbitrumConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                vrfCoordinator: 0x0000000000000000000000000000000000000000,
                gasLane: 0x0,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E,
                deployerKey: vm.envUint("PRIVATE_KEY"),
                priceFeed: 0x0000000000000000000000000000000000000000,
                ccipRouter: 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165,
                donId: bytes32("unknown")
            });
    }

    function getSepoliaBaseConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                vrfCoordinator: 0x0000000000000000000000000000000000000000,
                gasLane: 0x0,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
                deployerKey: vm.envUint("PRIVATE_KEY"),
                priceFeed: 0x0000000000000000000000000000000000000000,
                ccipRouter: 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93,
                donId: bytes32("unknown")
            });
    }

    function getFujiAvaxConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                vrfCoordinator: 0x2eD832Ba664535e5886b75D64C46EB9a228C2610,
                gasLane: 0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846,
                deployerKey: vm.envUint("PRIVATE_KEY"),
                priceFeed: 0x86d67c3D38D2bCeE722E601025C25a575021c6EA,
                ccipRouter: 0xF694E193200268f9a4868e4Aa017A0118C9a8177,
                donId: bytes32("fun-avalanche-fuji-1")
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        uint96 baseFee = 0.25 ether; // 0.25 LINK
        uint96 gasPriceLink = 1e9; // 1 gwei LINK

        vm.startBroadcast();
        VRFCoordinatorV2Mock vrfCoordinatorMock = new VRFCoordinatorV2Mock(
            baseFee,
            gasPriceLink
        );
        LinkToken link = new LinkToken();
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(
            DECIMALS,
            INITIAL_PRICE
        );
        vm.stopBroadcast();

        return
            NetworkConfig({
                vrfCoordinator: address(vrfCoordinatorMock),
                gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: address(link),
                deployerKey: DEFAULT_ANVIL_KEY,
                priceFeed: address(mockPriceFeed),
                ccipRouter: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
                donId: bytes32("fun-ethereum-sepolia-1")
            });
    }
}
