//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {console} from "forge-std/console.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DSCEngine, DecentralizedStableCoin, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address defaultOwner,
            address weth,
            address wbtc,
            address wethPriceFeed,
            address wbtcPriceFeed,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeed, wbtcPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(defaultOwner);
        // console.log("I rreached here yoo");
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        vm.stopBroadcast();
        dsc.transferOwnership(address(dscEngine));
        // console.log("I rreached here hehe");
        //so if i don't transfer the ownership of the contract,it means I can burn and mint tokens and it would become centralized ,so it's better to transfer it to engine to ensure transparency.

        return (dscEngine, dsc, helperConfig);
    }
}
