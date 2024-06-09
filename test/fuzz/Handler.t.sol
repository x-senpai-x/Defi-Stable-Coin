//narrows down the function calls
//eg we don't need to call redeem collateral function if there is no collateral to redeem
//we only call functions which won't revert

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
contract Handler is Test{
  
  DSCEngine dscEngine ;
  DecentralizedStableCoin dsc;
  ERC20Mock weth;
  ERC20Mock wbtc;
  address[] public usersWithDepositedCollateral; 
  uint256 MAX_DEPOSIT_SIZE=type(uint96).max;//max uint256 there is a problem since if we go for max uint 256 and then we want to deposit 
  uint256 countMint;
  MockV3Aggregator ethUsdPriceFeed;
  //more collateral we can't
  constructor(DSCEngine _dscEngine,DecentralizedStableCoin _dsc){
    dscEngine = _dscEngine;
    dsc = _dsc;
    address[] memory collateralTokens=dscEngine.getCollateralTokens();
    weth = ERC20Mock(collateralTokens[0]);
    wbtc = ERC20Mock(collateralTokens[1]);
    ethUsdPriceFeed = MockV3Aggregator(dscEngine.(address(weth)));
      }
  function mintDsc (uint256 amount , uint256 addressSeed) public{
    if (usersWithDepositedCollateral.length==0){
      return;
    }
    address sender=usersWithDepositedCollateral[addressSeed%usersWithDepositedCollateral.length];
    (uint256 totalDSCMinted,uint256 collateralValueInUsd)=dscEngine.getAccountInformation(sender);
    int256 maxDscToMint=int256(collateralValueInUsd)/2-int256(totalDSCMinted);
    if (maxDscToMint<0){
      return;
    }
    amount=bound(amount,0,uint256(maxDscToMint));
    if (amount==0){
      return;
    }
    vm.startPrank(sender);
    dscEngine.mintDsc(amount);
    vm.stopPrank();
    countMint++;

  }
  function depositCollateral(uint256 collateralSeed,uint256 amountCollateral) public{
    ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    amountCollateral=bound(amountCollateral,1,MAX_DEPOSIT_SIZE);
    //bounds the collateral amount b/w 1 and max deposit size
    vm.startPrank(msg.sender);
    collateral.mint(msg.sender,amountCollateral);//mint collateral to the user
    collateral.approve(address(dscEngine),amountCollateral);//whoever is calling this function should approve this contract to spend their collateral
    dscEngine.depositCollateral(address(collateral),amountCollateral);

    vm.stopPrank();
    //double push 
    usersWithDepositedCollateral.push(msg.sender);  
  }
  function redeemCollateral(uint256 collateralSeed,uint256 amountCollateral) public{
    ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    uint256 maxCollateralToRedeem=dscEngine.getCollateralBalanceOfUser(msg.sender,address(collateral));
    amountCollateral=bound(amountCollateral,0,maxCollateralToRedeem);
    if (amountCollateral==0){
      return;
    }
    dscEngine.redeemCollateral(address(collateral),amountCollateral);
  }
  function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
    if ((collateralSeed)%2==0){
      return weth;
    }
    else{
      return wbtc;
    }
  }
}
