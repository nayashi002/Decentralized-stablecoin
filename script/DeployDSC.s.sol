// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script{
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function run() external returns(DecentralizedStableCoin,DSCEngine,HelperConfig){
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config =  helperConfig.getConfig();
        tokenAddresses = [config.weth,config.wbtc];
        priceFeedAddresses = [config.wethUsdPriceFeed,config.wbtcUsdPriceFeed];
        vm.startBroadcast(config.account);
        DecentralizedStableCoin decentralizedStableCoin = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(decentralizedStableCoin));
        decentralizedStableCoin.transferOwnership(address(engine));
        vm.stopBroadcast();
        return(decentralizedStableCoin,engine,helperConfig);
    }
}