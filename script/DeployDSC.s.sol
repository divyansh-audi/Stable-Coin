//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DSCEngine, DecentralizedStableCoin) {
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
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(dscEngine)); //so if i don't transfer the ownership of the contract,it means I can burn and mint tokens and it would become centralized ,so it's better to transfer it to engine to ensure transparency.

        vm.stopBroadcast();

        return (dscEngine, dsc);
    }
}
