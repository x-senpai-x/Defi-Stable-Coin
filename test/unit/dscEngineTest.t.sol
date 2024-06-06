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
  address public weth;
  address public USER=makeAddr("user");

  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

  function setUp() external{
    DeployDSC deployer = new DeployDSC();
    (dsc,dscEngine,helperConfig) = deployer.run();
    (ethUsdPriceFeed,,weth,,)=helperConfig.activeNetworkConfig();
    ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
  }
  function testGetUsdValue() public {
    //we need pricefeeds for this which are stored in helper config
    //we can get helperconfig from deploy script byh poroviding it in return
    
    uint256 ethAmount=15e18;//15eth
    //2000 dollars per eth
    //15e18*2000/eth =30000 e18
    uint256 expectedUsd=3000e18;//problem with 30000
    uint256 actualUsd=dscEngine.getUsdValue(weth,ethAmount);
    //btcUsdPriceFeed,wbtc and deployerKey are not needed
    assertEq(actualUsd,expectedUsd);
  }

  function testRevertsIfCollateralZero() public{
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
    vm.expectiRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
    dscEngine.depositCollateral(weth,0);

    vm.stopPrank();
  }

}