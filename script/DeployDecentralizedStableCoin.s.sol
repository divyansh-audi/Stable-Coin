//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract DeployDecentralizedStableCoin is Script {
    DecentralizedStableCoin deploy;
    address defaultOwner = 0x818c95937Cf7254cE5923e4E1dBf2fAF0dDaD06E;

    function run() external returns (DecentralizedStableCoin) {
        vm.startBroadcast();
        deploy = new DecentralizedStableCoin(defaultOwner);
        vm.stopBroadcast();
        return deploy;
    }
}
