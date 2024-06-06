// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "../lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import { ERC20Mock } from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/mocks/ERC20Mock.sol";
contract HelperConfig is Script{
  uint8 public constant DECIMALS = 8;
  int256 public constant ETH_USD_PRICE = 200e8;
  int256 public constant BTC_USD_PRICE = 100e8;
  uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
  //weth is ERC20 version of ETHereum
  struct NetworkConfig {
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
  }
  NetworkConfig public activeNetworkConfig;
  
  constructor() {
    if (block.chainid==11155111){
      activeNetworkConfig = getSepoliaEthConfig();}
    else {
      activeNetworkConfig = getOrCreateAnvilEthExchange();
    }
    }
  
  function getSepoliaEthConfig() public view  returns (NetworkConfig memory) {
    //If function is pure, we can't use vm.envUint since it reads from 
    NetworkConfig memory sepoliaConfig= NetworkConfig({
      wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
      wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
      weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
      wbtc: 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC,
      deployerKey: vm.envUint("PRIVATE_KEY")
    });
    return (sepoliaConfig);
  }
  function getOrCreateAnvilEthExchange() public returns(NetworkConfig memory){
    if(activeNetworkConfig.wethUsdPriceFeed!=address(0)){
      return activeNetworkConfig;
    }
    vm.startBroadcast();
    MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
    ERC20Mock wethMock = new ERC20Mock("WETH", "WETH",msg.sender,1000e8);
    ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC",msg.sender,1000e8);
    MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
    
    vm.stopBroadcast();
    return NetworkConfig({
      wethUsdPriceFeed: address(ethUsdPriceFeed),
      wbtcUsdPriceFeed: address(btcUsdPriceFeed),
      weth: address(wethMock),
      wbtc: address(wbtcMock),
      deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
      //deployer Key extracted from anvil chain                                         

    });
  }
}