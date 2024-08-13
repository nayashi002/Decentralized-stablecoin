// SPDX-License-Identifier: MIT
// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions
// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author Ibrahim Nayashi
 *
 * The system is designed to be as minimal as possible and have the token maintain a 1 token == 1$ peg.
 * This stablecoin has the properties
 * - Extrogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * it is similar to DAI if DAI has no governance, no fees, and is only backed by WETH or WBTC
 *
 * our DSC system should always be "overcollaterized" and at no point, should the value of all the collateral
 * be less than or equal The $ backed value of all the DSC
 *
 *
 * @notice This contract is the core of the DSC System. it handles all the logic for minting
 * and redeeming DSC as well as depositing and withdrawing collateral
 * @notice This contract is VERY loosely based on the MakerDao DSS DAI system
 *
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////// 
    //    Errors     //
    /////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOk();
    error DSCEngine__HealthFactorNotImproved();

     ////////////////// 
    //    Types     //
    /////////////////
    using OracleLib for AggregatorV3Interface;
    ////////////////////
    //State Variables ////
    ////////////////////
    uint256 public constant LIQUIDATION_THRSHOLD = 50;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
     uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
      uint256 private constant PRECISION = 1e18;
      uint256 private constant LIQUIDATION_BONUS = 10;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted; // Keeps tracks of amount User minted
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;
     
     //////////////////
    //    Events  //// 
    /////////////////

    event CollateralDeposited(address indexed user,address indexed token,uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemTo,address indexed token,uint256 amount);

    //////////////////
    // Modifiers  ////
    /////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////
    // Function   ///
    /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH / USD, BTC / USD, MKR / USD etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////
    //// External Functions///
    ////////////////////////

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToMint the amount of decentralized token to mint
     * @notice this function will deposit your collateral and mint Dsc in one transaction
     */
    function depositCollateralAndMintDSC(address tokenCollateralAddress,uint256 amountCollateral,uint256 amountDscToMint) external {
       depositCollateral(tokenCollateralAddress, amountCollateral);
       mintDSC(amountDscToMint);
    }
    /**
     *@notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);
        bool success =IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }
   /**
    * 
    * @param tokenCollateralAddress The collateral Address to redeem
    * @param amountCollateral The amount of collateral
    * @param amountDscToBurn amount of stable coin to burn
    */
    function redeemCollateralForDSC(address tokenCollateralAddress,uint256 amountCollateral,uint256 amountDscToBurn) external {
     burnDSC(amountDscToBurn);
     redeemCollateral(tokenCollateralAddress, amountCollateral);
    }
    /**
     * @notice in order to redeem collateral
     * 1. health factor must be over 1 or 1e18
     * @notice follows CEI
     */

    function redeemCollateral(address tokenCollateralAddress,uint256 amountCollateral) public moreThanZero(amountCollateral)nonReentrant{
      _redeemCollateral(msg.sender,msg.sender, tokenCollateralAddress,amountCollateral);
     _revertIfHealthFactorIsBroken(msg.sender);
    }
    // 100 ETH
    // 100 break
    // 1. burn
    // 2. redeem ETH
    /**
     * Simply means if he has $100 ETH in collateral and borrows $20 worth of DSC he has to burn his DSC first 
     * This allows the user not to redeem and also holds the DSC major critical
     *  
     */
    /**
     * 
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public  moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint; //Keeps tracks of minted amount
        // if they minted too much say $150 DSC and have $100 ETH
      _revertIfHealthFactorIsBroken(msg.sender);
      bool minted = i_dsc.mint(msg.sender,amountDscToMint);
      if(!minted){
        revert DSCEngine__MintFailed();
      }
    }

    function burnDSC(uint256 amount) public{
       
       _burnDsc(amount,msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    // if we do start nearing undercollaterization,we need someone to ilquidate our position

    // we need $100 backing $50 DSC
    // we cant have $20 backing $50 worth of DSC<- DSC wont be worth $1

    // if we have $75 backing $50 worth of DSC it is worth below our 50% threshold
    // hence the liquidator takes the $75 backing and pays of $50 DSC or burns it in doing this it creates a free $25 profit incentive 
     
    // if someone is almost undercollaterized we would pay another user to liquidate their position (ie creating a profit incentive)
    /**
     * @param collateralAddress the erc20 collateral address to liquidate from the user
     * @param user the user whose health factor is broken. their health factor should be below MIN_HEALTH_FACTOR
     * @param debtToCover the amount of DSC to burn to improve user health factor
     * 
     * @notice you can partially liquidate the user
     * @notice you will get a liquidation bonus for taking the user funds
     * @notice this function assumes that the sysytem is atleast overcollaterized in order to work
     * @notice a known bug would be if the protocol were 100% or less undercollaterized, then we wouldnt be able to incentivise the liquidators
     * for example if the price plummeted before anyone could be liquidated
     * Face CEI checks effects and interactions
     */
    function liquidate(address collateralAddress,address user,uint256 debtToCover) external moreThanZero(debtToCover)nonReentrant{
        // need to check user health factor
     uint256 startingUserHealthFactor = _healthFactor(user);
     if(startingUserHealthFactor >= MIN_HEALTH_FACTOR){
        revert DSCEngine__HealthFactorIsOk();
     }
     // we want to burn their DSC debt
     // And take their collateral
     // Bad User $140 ETH,$100 below 1.5 threshold
     // debt to cover = $100
     // $100 of DSC == ?? ETH
     // 0.5 ETH
     uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralAddress,debtToCover);
     // and give them a 10% bonus
     // so we are giving the liquidators $110 WETH for $100 DSC
     // we should implement a feature to liquidate in the case that the protocol is insolvent
     // and sweep extra amount into treasury
     // 0.5 ETH * 0.1 = 0.05 ETH
     uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
     uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
     _redeemCollateral(user, msg.sender, collateralAddress,totalCollateralToRedeem); 
     _burnDsc(debtToCover, user, msg.sender);
     uint256 endingUserHealthFactor = _healthFactor(user);
     if(endingUserHealthFactor <= startingUserHealthFactor){
        revert DSCEngine__HealthFactorNotImproved();
     }
     _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external {}
    
    ////////////////////////////////////////
    // Private & internal view Functions   ///
    ////////////////////////////////////////
    function _redeemCollateral(address from,address to,address tokenCollateralAddress,uint256 amountCollateral) private {
   s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
     emit CollateralRedeemed(from,to,tokenCollateralAddress,amountCollateral);
     bool success = IERC20(tokenCollateralAddress).transfer(to,amountCollateral);
     if(!success){
        revert DSCEngine__TransferFailed();
    }
    }
    /**
     * @dev low-level internal function, do not call unless the function calling
     * it is checking for health factor being broken
     */
   function _burnDsc(uint256 amountDscToBurn,address onBehalfOf,address dscFrom) private moreThanZero(amountDscToBurn){
     s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom,address(this),amountDscToBurn);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
   }
   function getTokenAmountFromUsd(address token,uint256 usdAmountInWei) public view returns(uint256){
    //if we have a price of ETH to be $2000 and we have a $1000 worth of ETH then the amount of ETH in our possession is $1000/$2000 = 0.5 ETH
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (,int256 price,,,) = priceFeed.staleChecksLatestRoundData();
    // ($100e18 * 1e18) / ($2000e8 * 1e10)
    return (usdAmountInWei * PRECISION)/(uint256(price) * ADDITIONAL_FEED_PRECISION);
   }
    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted,uint256 collateralValueInUsd){
     totalDscMinted = s_DSCMinted[user];
     collateralValueInUsd  = getAccountCollateralValueInUsd(user);
    }
    /**
     * 
     * Returns how close to iquidation a user is
     * if a user goes below 1,then they get liquidated
     */
    function _healthFactor(address user) private view returns(uint256){
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted,uint256 collateralValueInUsd) = _getAccountInformation(user);
       
        // the above statement basically calculates the threshold say if the user collateral value in usd is $150 and is multiplied by 50
        // which in turn gives $7500 which is then divided by 100 which in turn gives $75 this is the liquidation threshold 
     return _calculateHealthFactor(totalDscMinted,collateralValueInUsd);
    }
    function _revertIfHealthFactorIsBroken(address user) internal view{
        // 1. Check health factor (do they have enough collateral)
        // 2. Revert if they don't
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
           revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
      ////////////////////////////////////////
    // Public & External view Functions   ///
    ////////////////////////////////////////
    
    function getAccountCollateralValueInUsd(address user) public view returns(uint256 totalCollateralValueInUsd){
        // loop through each collateral token, get the amount they have deposited, and map it to the price to get the USD value
         for(uint256 i =0; i < s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token,amount);
         }
         return totalCollateralValueInUsd;
    }
    function getUsdValue(address token,uint256 amount) public view returns(uint256){
     AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
     (,int256 price,,,) = priceFeed.staleChecksLatestRoundData();
     // 1 ETH = $1000
     // The returned value for CL will be 100 * 1e8
     return(uint256(price) * ADDITIONAL_FEED_PRECISION) * amount / PRECISION;

    }
    function _calculateHealthFactor(uint256 totalDscMinted,uint256 collateralValueInUsd) internal pure returns(uint256){
      if (totalDscMinted == 0) return type (uint256).max;
      uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRSHOLD) / LIQUIDATION_PRECISION;
      return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
    }

    function getAccountInformation(address user) public view returns(uint256 totalDscMinted,uint256 collateralValueInUsd){
        (totalDscMinted,collateralValueInUsd) = _getAccountInformation(user);
    }
    function getHealthFactor(address user) external view returns(uint256){
        return _healthFactor(user);
    }
    function calculateHealthFactor(uint256 totalDscMinted,uint256 collateralValueInUsd) external pure returns(uint256){
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    function getAdditionalFeedPrecision() external pure returns(uint256){
        return ADDITIONAL_FEED_PRECISION;
    }
    function getLiquidationThreshold() external pure returns(uint256){
        return LIQUIDATION_THRSHOLD;
    }
    function getLiquidationPrecision() external pure returns(uint256){
        return LIQUIDATION_PRECISION;
    }
    function getLiquidationBonus() external pure returns(uint256){
        return LIQUIDATION_BONUS;
    }
    function getMinHealthFactor() external pure returns(uint256){
        return MIN_HEALTH_FACTOR;
    }
    function getCollateralArray() external view returns(address[] memory){
        return s_collateralTokens;
    }
    function getDsc() external view returns(address){
        return address(i_dsc);
    }
    function getPriceFeed(address token) external view returns(address){
        return s_priceFeeds[token];
    }
    function getCollateralDepositedFromUser(address user,address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }
    function _getUsdValue(address token,uint256 amount) external view returns(uint256){
        return getUsdValue(token, amount);
    }
}      