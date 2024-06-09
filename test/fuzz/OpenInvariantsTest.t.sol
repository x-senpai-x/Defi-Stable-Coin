//First thing to do:

//What are our invariants i.e what are the properties which should always hold true

//1.Total Supply of DSC should always be less than total collateral available
//2.Getter view functions should never revert.  Note This is an evergreen invariant
/*
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract OpenInvariantsTest is StdInvariant,Test{
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    function setUp() external{
      deployer = new DeployDSC();
      (dsc,dscEngine,config) = deployer.run();
      (,,weth,wbtc,)=config.activeNetworkConfig();
      targetContract(address(dscEngine));  //target contract : The contract where we need to call fns from
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply ()public view{
      uint256 totalSupply=dsc.totalSupply();
      //we want to get total weth deposited 
      uint256 totalWethDeposited=IERC20(weth).balanceOf(address(dscEngine));
      uint256 totalWbtcDeposited=IERC20(wbtc).balanceOf(address(dscEngine));
      uint256 wethValue= dscEngine.getUsdValue(address(weth),totalWethDeposited);//in usd
      uint256 wbtcValue= dscEngine.getUsdValue(address(wbtc),totalWbtcDeposited);//in usd
      uint256 totalValue=wethValue+wbtcValue;
      console.log("wethValue",wethValue);
      console.log("wbtcValue",wbtcValue);
      console.log("totalValue",totalValue);
      console.log("totalSupply",totalSupply);
      assert(totalValue>=totalSupply);
    }

    }
  */