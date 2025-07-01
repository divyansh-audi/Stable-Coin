// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address defaultOwner;
        address weth;
        address wbtc;
        address wethPriceFeed;
        address wbtcPriceFeed;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_Price = 1000e8;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
        // activeNetworkConfig = getSepoliaEthConfig();
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            defaultOwner: msg.sender,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("defaultKey")
        });
        return sepoliaConfig;
    }

    // function getNetworkConfig() public returns(NetworkConfig memory){

    // }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_Price);
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();
        // NetworkConfig memory anvilConfig = NetworkConfig({
        //     defaultOwner: msg.sender,
        //     weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
        //     wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
        //     wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
        //     wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
        //     deployerKey: vm.envUint("myAnvilKey")
        // });
        // return anvilConfig;
        return NetworkConfig({
            defaultOwner: msg.sender,
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            wethPriceFeed: address(ethUsdPriceFeed),
            wbtcPriceFeed: address(btcUsdPriceFeed),
            deployerKey: vm.envUint("MY_ANVIL_KEY")
        });
    }
}
