// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; //to prevent reentrancy attacks
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
//ipricefeed can also be used
/*
Similar to DAI if DAI had no governance, no fee and was only backed by wETH and wBTC
Accounts for 
minting , redeeming DSC and  
depositing , withdrawing collateral  */

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressMustBeOfSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);


    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200 percent overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    DecentralizedStableCoin private immutable i_dsc;

    address[] private s_collateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    //using indexed in events allows for efficient filtering and searching of specific events based
    //on the values of the indexed parameters.
    //Max 3 parameters can be indexed in an event

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeed[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressMustBeOfSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddress[i]; //sets up what tokens are allowed in our contract
            //each tokenAddress has its own price feed contract address using which the price of token can be fetched
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
        //decentralized stable coin contract address is passed as argument to this contract
    }

    function depositCollateralAndMintDsc() external {}

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //user deposits collateral in this function
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        //since transferFrom returns bool
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralforDsc() external {}
    function redeemCollateral() external {}

    function mintDsc(uint256 amountDscToMint) external nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //ensure user hasn't minted more than threshold
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted= i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    //burnDsc required so that if value of DSC with user is approaching near collateral i.e token is no longer
    // overcollateralized then user can burn DSC so that collateral is released and user can redeem collateral anytime

    function burnDsc() external {}
    //user should get liquidated if value of DSC with user is less than collateral i.e if collateral goes below a certain threshold value
    //if certain person sees that collateral falls below a certain value then he can call this function to liquidate user
    function liquidate() external {}
    function getHealthFactor() external {}
    //health factor is ratio of value of collateral to value of DSC
    //if a user goes below 1 they can get liquidated

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            //get amount of each token deposited by user
            //get price of each token from price feed in USD
            //multiply price of token with amount of token deposited by user
            //add all the values of token deposited by user
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return (totalCollateralValueInUsd);
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount / PRECISION);
        /*
        latestRoundData() returns a tuple with the latest round data includes 
        roundId (uint80)
        answer (int256) — The latest price.
        startedAt (uint256) — Timestamp of when the round started.
        updatedAt (uint256) — Timestamp of when the round was updated.
        answeredInRound (uint80) — The round ID in which the answer was computed. 
        allows your contract to fetch real-time price data from Chainlink's decentralized oracles, 
        ensuring your contract can make decisions based on current market prices.*/
        //if 1ETH=$1000 then returned value will be 1000*10^8
        //1000*1e8*1e10*1000/1e18 (amount is 1000)
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) internal view returns (uint256) {
        //value of collateral / value of DSC
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        //return (collateralValueInUsd/totalDscMinted); this returns float value
        //shld be always greater than 1 or maybe above a certain number greater than 1
        uint256 collateralAdjustedForThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        //eg say 1000ETH deposited as collateral
        //1000 *50/100=500
        //if value of DSC is more than 500 then user can be liquidated
        //1000ETH/500DSC=2 so health factor is 2
        return (collateralAdjustedForThreshold * PRECISION / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view  {
        uint256 userHealthFactor = _healthFactor(user);
        if ( userHealthFactor< MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
}
