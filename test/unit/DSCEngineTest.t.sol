// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {Test,console} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3AggregatorV3.sol";

contract DSCEngineTest is Test{
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
     event CollateralDeposited(address indexed user,address indexed token,uint256 indexed amount);
     event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemTo,address indexed token,uint256 amount);
   address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        address account;
        address public USER = makeAddr("user");
        address public LIQUIDATOR = makeAddr("liquidator");
        address public ZERO_ADDRESS = address(0);
        uint256 public  AMOUNT_COLLATERAL = 10 ether;
        uint256 public COLLATERAL_TO_COVER = 20 ether;
        uint256 public  AMOUNT_TO_MINT = 100 ether;
        uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
        uint256 public constant LIQUIDATION_THRSHOLD = 50;
        uint256 public constant LIQUIDATION_PRECISION = 10000;
         uint256 private constant PRECISION = 1e18;
      function setUp() public{
        deployer = new DeployDSC();
        (dsc,dsce,helperConfig) = deployer.run();
       HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
       wethUsdPriceFeed = config.wethUsdPriceFeed;
       wbtcUsdPriceFeed = config.wbtcUsdPriceFeed;
       weth = config.weth;
       wbtc = config.wbtc;
       account = config.account;
      //  wethUsdPriceFeed = address(new MockV3Aggregator(8, 2000e8)); // Mocking 2000 USD per ETH
    // wbtcUsdPriceFeed = address(new MockV3Aggregator(8, 50000e8));
       ERC20Mock(weth).mint(USER,AMOUNT_COLLATERAL);
   ERC20Mock(weth).mint(LIQUIDATOR,COLLATERAL_TO_COVER);
      //  vm.deal(USER, STARTING_ERC20_BALANCE);
      //  vm.deal(LIQUIDATOR,STARTING_ERC20_BALANCE);

      }
      //////////////////
      /// Price Test////
      //////////////////
      address[] public tokenAddresses;
      address[] public priceFeedAddresses;
   function testRevertsIfPriceLengthNotEqual() public{
     tokenAddresses.push(weth);
     priceFeedAddresses.push(wbtcUsdPriceFeed);
     priceFeedAddresses.push(wethUsdPriceFeed);
     vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
     new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
   }
  //  function testPassesIfPriceLengthEqual() public{
  //    tokenAddresses.push(weth);
  //    tokenAddresses.push(wbtc);
  //    priceFeedAddresses.push(wbtcUsdPriceFeed);
  //    priceFeedAddresses.push(wethUsdPriceFeed);
  //    new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
  //  }

      function testGetUsdValue() public view{
       uint256 ethAmount = 15e18;
         uint256 expectedUsd = 30000e18;
         uint256 actualUsd = dsce.getUsdValue(weth,ethAmount);
         assertEq(expectedUsd,actualUsd);
      }
      function testGetTokenAmountFromUsd() public view{
        uint256 usdAmount = 100 ether;
        // $2000 /ETH,$100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth,actualWeth);
      }
      function testRevertsIfCollateralIsZero() public{
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
      }
     modifier depositCollateral(){
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
      dsce.depositCollateral(weth,AMOUNT_COLLATERAL);
      vm.stopPrank();
      _;
     }
      modifier depositedCollateralAndMintedDsc() {
     vm.startPrank(USER);
     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
     dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
     vm.stopPrank();
     _;
 }
     function testRevertsWithUnapproveCollateral() public depositCollateral{
      ERC20Mock ranToken = new ERC20Mock();
      vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
      dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
      
     }
     function testCanDepositCollateralAndGetAccountInfo() public depositCollateral{
    (uint256 totalDscMinted,uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
      
      uint256 expectedTotalDscMinted = 0;
      uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
      assertEq(totalDscMinted,expectedTotalDscMinted);
      assertEq(AMOUNT_COLLATERAL,expectedDepositAmount);
      // 2000,0000000000000000000 
      // 10000000000000000000
     }
     function testEmitsAfterDeposit() public {
       vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
       vm.expectEmit(true,true,true,false);
      emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
      dsce.depositCollateral(weth,AMOUNT_COLLATERAL);
      vm.stopPrank();
       
      }

  function testHealthFactorRevertsIfCalculationNotOkay() public depositCollateral {
    uint256 healthFactor = 0;
    vm.expectRevert(
        abi.encodeWithSelector(
            DSCEngine.DSCEngine__BreaksHealthFactor.selector,
            healthFactor
        )
    );
     
    dsce.mintDSC(AMOUNT_COLLATERAL * 2);
}
 function testRevertsIfMintAmountIsZero() public depositedCollateralAndMintedDsc{
  vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
  dsce.mintDSC(0);

 }
 function testUserCanMint() public{
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
     dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
     dsce.mintDSC(AMOUNT_TO_MINT);
     vm.stopPrank();
}
 function testRevertIfHealthFactorIsBroken() public{
 (,int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
 AMOUNT_TO_MINT = (AMOUNT_COLLATERAL * (uint256(price) * dsce.getAdditionalFeedPrecision())) / PRECISION;
 vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
 uint256 expectedHealthFactor = dsce.calculateHealthFactor(AMOUNT_TO_MINT,dsce._getUsdValue(weth,AMOUNT_COLLATERAL));
   vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
vm.stopPrank();
 

 }
 function testUserCollateralDepositedIsStored() public{
    uint256 safeMint =AMOUNT_COLLATERAL /1000;
     (,int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
    AMOUNT_TO_MINT = ( safeMint * (uint256(price) * dsce.getAdditionalFeedPrecision())) / PRECISION;
     vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
 dsce.getCollateralDepositedFromUser(USER, weth);
    assertEq(AMOUNT_COLLATERAL,dsce.getCollateralDepositedFromUser(USER, weth));
uint256 contractBalance = ERC20Mock(weth).balanceOf(address(dsce));
    assertEq(contractBalance,AMOUNT_COLLATERAL);
vm.stopPrank();

 }
 function testUserCanRedeemCollateral() public{
  vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
  dsc.approve(address(dsce),AMOUNT_TO_MINT);
    dsce.redeemCollateralForDSC(weth,AMOUNT_COLLATERAL,AMOUNT_TO_MINT);
vm.stopPrank();
uint256 userbalance = dsc.balanceOf(USER);
assertEq(userbalance,0);
 }
 function testRevertsIFCollateralToRedeemIsZero()public{
   vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
  dsc.approve(address(dsce),AMOUNT_TO_MINT);
  vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dsce.redeemCollateralForDSC(weth,0,AMOUNT_TO_MINT);
vm.stopPrank();
 }
 function testBurningToken() public{
  vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
  dsc.approve(address(dsce),AMOUNT_TO_MINT);
     dsce.burnDSC(AMOUNT_TO_MINT);
vm.stopPrank();
   
 }
 function testCantBurnZeroDSC() public{
  vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
   vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
 dsce.burnDSC(0);
vm.stopPrank();
 }
 function testRedeemCollateralAfterBurning() public{
  vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
  dsc.approve(address(dsce),AMOUNT_TO_MINT);
     dsce.burnDSC(AMOUNT_TO_MINT);
     dsce.redeemCollateral(weth,AMOUNT_COLLATERAL);
vm.stopPrank();
 }
 function testCantRedeemZeroCollateralAfterBurning() public{
   vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
  dsc.approve(address(dsce),AMOUNT_TO_MINT);
     dsce.burnDSC(AMOUNT_TO_MINT);
     vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
     dsce.redeemCollateral(weth,0);
vm.stopPrank();
 }
 function testMintingIsSuccessFull() public{
   vm.startPrank(USER);
  ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
  vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MintingNotToZeroAddress.selector);
  dsc.mint(address(0),AMOUNT_COLLATERAL);
  // dsc.approve(address(dsce),AMOUNT_TO_MINT);
 }
 function testLiquidationRevertsIfHealthFactorIsOkay() public depositedCollateralAndMintedDsc{
   vm.prank(LIQUIDATOR);
   vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOk.selector);
   dsce.liquidate(weth, USER, AMOUNT_TO_MINT);
 }
 function testHealthFactorDepletesIfPriceDepletes() public depositedCollateralAndMintedDsc{
  int256 newEthUsdPrice = 18e8;
    MockV3Aggregator(wethUsdPriceFeed).updateAnswer(newEthUsdPrice);
   uint256 newUserHealthFactor = dsce.getHealthFactor(USER);
   assert(newUserHealthFactor < dsce.getMinHealthFactor());
   console.log(newUserHealthFactor);

  
 }
     function testEmitCollateralRedeemedWithCorrectArgs() public depositCollateral{
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    modifier liquidator(){
 vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDSC(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.liquidate(weth, USER, AMOUNT_TO_MINT); // We are covering their whole debt
        vm.stopPrank();
        _;
    }
 function testLiquidatorCanLiquidate() public liquidator{}
 
function testUserHasNoMoreDebtAfterLiquidation() public liquidator{
 (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
 assertEq(totalDscMinted,0);
}
function testLiquidatorTakesOnUsersDebt() public liquidator{
  (uint256 totalDscMinted,) = dsce.getAccountInformation(LIQUIDATOR);
  assertEq(totalDscMinted,AMOUNT_TO_MINT);
}
function testLiquidationPrecision() public view{
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
       function testGetLiquidationThreshold() public view{
        uint256 LIQUIDATION_THRESHOLD = 50;
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }
    function testGetLiquidationBonus() public view{
        uint256  LIQUIDATION_BONUS = 10;
        uint256 liquidationBonus = dsce.getLiquidationBonus();
        assertEq(liquidationBonus,LIQUIDATION_BONUS);
    }
    function testGetAddtionalFeedPrecision() public view{
        uint256 ADDITIONAL_FEED_PRECISION = 1e10;
        uint256 additionalFeedPrecision = dsce.getAdditionalFeedPrecision();
        assertEq(ADDITIONAL_FEED_PRECISION, additionalFeedPrecision);

    }
    function testGetCollateralArrayLengthIsNotZero() public view{
     address[] memory collateralArray = dsce.getCollateralArray();
      assertEq(collateralArray[0],weth);
      
    }
    function testGetsPriceFeeds() public{
      vm.prank(USER);
      address priceFeed = dsce.getPriceFeed(weth);
      priceFeedAddresses.push(wethUsdPriceFeed);
       assertEq(priceFeed, priceFeedAddresses[0]);
    }
}

