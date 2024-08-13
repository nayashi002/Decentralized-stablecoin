// SPDX-License-Identifier: MIT
// Have our Invariant aka properties

// What are our invariant

// 1. The total supply of DSC should always be less than the total value of collateral deposited

// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test,console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";


contract InvariantsTest is StdInvariant,Test{
      DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
    address wethUsdPriceFeed;
    Handler handler;
        address wbtcUsdPriceFeed;
       address weth;
        address wbtc;
        address account;
    function setUp() public {
      deployer = new DeployDSC();
  (dsc,dsce,helperConfig) = deployer.run();
handler = new Handler(dsce,dsc);
 targetContract(address(handler));
   HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
         wethUsdPriceFeed = config.wethUsdPriceFeed;
       wbtcUsdPriceFeed = config.wbtcUsdPriceFeed;
       weth = config.weth;
       wbtc = config.wbtc;
       account = config.account;
      
    }
    function invariant_protocolMustHaveMoreValueThanTotalSupply() external view{
      // get all the of the collateralin the protocol
      // compare it all to the debt
      uint256 totalSupply = dsc.totalSupply();
      uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
      uint256 totalWbthDeposited = IERC20(wbtc).balanceOf(address(dsce));
      
      uint256 wethValue = dsce.getUsdValue(weth,totalWethDeposited);
      uint256 wbtcValue = dsce.getUsdValue(wbtc,totalWbthDeposited);
  
      console.log("weth value:", wethValue);
      console.log("weth value:", wbtcValue);
      console.log("total supply:", totalSupply);
      console.log("Times mint been Called:", handler.timesMintIsCalled());
      assert(wethValue + wbtcValue >= totalSupply);
    }
}