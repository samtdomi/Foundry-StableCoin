// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "lib/forge-std/src/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    // DSCEngine Constructor Arguments:
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address public dscAddress;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeConfig();

        // DSCEngine constructor arguments populated IN ORDER:
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        // Deploys the DSC simple contract
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        dscAddress = address(dsc);

        // Deploys the ENGINE contract
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, dscAddress);

        // immediately transfers ownership of DSC contract to the ENGINE contract
        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (dsc, engine, helperConfig);
    }
}
