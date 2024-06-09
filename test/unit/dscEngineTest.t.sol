// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/mocks/ERC20Mock.sol";
contract DSCEngineTest is Test{
  DSCEngine public dscEngine;
  DecentralizedStableCoin public dsc;
  HelperConfig public helperConfig;

  address public ethUsdPriceFeed;
  address public btcUsdPriceFeed;
  address public weth;
  address public wbtc;
  address public USER=makeAddr("user");

  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
  uint256 public constant DSC_TO_MINT= 1 ;

  function setUp() external{
    DeployDSC deployer = new DeployDSC();
    (dsc,dscEngine,helperConfig) = deployer.run();
    (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,)=helperConfig.activeNetworkConfig();
    ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
  }
  //constructor test
  address[] public tokenAddresses;
  address[] public priceFeedAddresses;

  function testRevertsIfLengthTokenDoesntMatchPriceFeeds() public {
    tokenAddresses.push(weth );
    priceFeedAddresses.push(ethUsdPriceFeed);
    priceFeedAddresses.push(btcUsdPriceFeed);
    vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressMustBeOfSameLength.selector);
    new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));

  }

  //GetUsdValue fn

  function testGetUsdValue() public {
    //we need pricefeeds for this which are stored in helper config
    //we can get helperconfig from deploy script byh poroviding it in return
    //THIS TEST wont work on sepolia since it takes price from real time sepolia testnet which keeps getting updated 
    //ANvil chain allows us to use mock price feed where we can set our price as we want 
    uint256 ethAmount=15e18;//15eth/
    //2000 dollars per eth
    //15e18*2000/eth =30000 e18
    uint256 expectedUsd=30000e18;
    uint256 actualUsd=dscEngine.getUsdValue(weth,ethAmount);
    //btcUsdPriceFeed,wbtc and deployerKey are not needed
    assertEq(actualUsd,expectedUsd);
  }
//getTokenAmountFromUsd
  function testGetTokenAmountFromUsd() public{
    uint256 usdAmount=100 ether;//100 dollars
    // we want 100 dollars worth of weth
    //$2000 per eth
    uint256 expectedWeth=0.05 ether;//100/2000 
    uint256 actualWeth=dscEngine.getTokenAmountFromUsd(weth,usdAmount);
    assertEq(actualWeth,expectedWeth);
  }
  //depositCollateral fn
  function testRevertsIfCollateralZero() public{
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
    //allows a token holder to grant another address permission to transfer up to a specified amount of tokens on their behalf.
    vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
    dscEngine.depositCollateral(weth,0);

    vm.stopPrank();
  }
  function testRevertsIfNotAllowedCollateralUsed() public {
    ERC20Mock ranToken= new ERC20Mock("Ran","Ran",USER,AMOUNT_COLLATERAL);//we create a new user
    vm.startPrank(USER);
    vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
    dscEngine.depositCollateral(address(ranToken),AMOUNT_COLLATERAL);
    vm.stopPrank();
  }
  modifier depositedCollateral(){
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
    ERC20Mock(wbtc).approve(address(dscEngine),AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(weth,AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(wbtc,AMOUNT_COLLATERAL);
    vm.stopPrank();
    _;
  }
  
  function testCanDepositCollateralAndGetAccountInformation() public depositedCollateral {
    (uint256 totalDscMinted, uint256 collateralValueInUsd)=dscEngine.getAccountInformation(USER);
    uint256 expectedDscMinted=0;
    uint256 expectedCollateralValueInUsd=dscEngine.getUsdValue(weth,AMOUNT_COLLATERAL) + dscEngine.getUsdValue(wbtc,AMOUNT_COLLATERAL);
    
    //uint256 expectedDepositAmount=dscEngine.getTokenAmountFromUsd(weth,collateralValueInUsd);
    assertEq(expectedDscMinted,totalDscMinted);
    assertEq(collateralValueInUsd,expectedCollateralValueInUsd);
    //assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
  }
  //redeemCollateral
  

  //function


}