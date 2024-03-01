// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {PortalGate} from "../src/PortalGate.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPortalGate is Script {
    function run() external returns (PortalGate) {
        HelperConfig helperConfig = new HelperConfig();
        (, , , , address link, , , address ccipRouter, ) = helperConfig
            .activeNetworkConfig();
        vm.startBroadcast();
        PortalGate portalGate = new PortalGate(ccipRouter, link);
        vm.stopBroadcast();

        return portalGate;
    }
}
