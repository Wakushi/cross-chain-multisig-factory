// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {PortalSigFactory} from "../src/PortalSigFactory.sol";

contract DeployPortalSigFactory is Script {
    function run() external returns (PortalSigFactory) {
        vm.startBroadcast();
        PortalSigFactory portalSigFactory = new PortalSigFactory();
        vm.stopBroadcast();

        return portalSigFactory;
    }
}
