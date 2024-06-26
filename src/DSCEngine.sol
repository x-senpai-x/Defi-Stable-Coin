// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
/*
Similar to DAI if DAI had no governance, no fee and was only backed by wETH and wBTC
Things that can be done
Depositing an allowed collateral token anytime
Minting any amount of DSC token below the threshold collateral anytime
Burning dsc token to release collateral anytime
Redeeming collateral anytime    
Liquidating a user if their health factor goes below 1
Getting health factor of a user
Getting account collateral value in USD
*/

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; //to prevent reentrancy attacks
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
//ipricefeed can also be used

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressMustBeOfSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved(); 


    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200 percent overcollateralized
    //percentage threshold at which the collateral is considered safe from liquidation.

    uint256 private constant LIQUIDATION_PRECISION = 100;
    //used to provide precision to the threshold calculation. It is set to 100 to represent the percentage base.
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS =10;

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    DecentralizedStableCoin private immutable i_dsc;

    address[] private s_collateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo ,address indexed token, uint256 amount);
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
    //external functions can only be called from outside the contract
    //below functions are external because they are called by users or other contracts

    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral,uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //collateral token address , amount of collateral to be deposited

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        //When you call emit with an event, it creates a log entry on the blockchain.
        //This log entry contains the data specified in the event parameters.
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        //since transferFrom returns bool
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralforDsc(address tokenCollateralAddress,uint256 amountCollateral,uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress,amountCollateral);
    }
    function redeemCollateral(address tokenCollateralAddress,uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {        
    //to redeemCollateral HF > 1 after collateral has been removed
        _redeemCollateral(msg.sender,msg.sender,tokenCollateralAddress,amountCollateral);//doubt
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    

    function mintDsc(uint256 amountDscToMint) public nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //ensure user hasn't minted more than threshold
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    //burnDsc required so that if value of DSC with user is approaching near collateral i.e token is no longer
    // overcollateralized then user can burn DSC so that collateral is released and user can redeem collateral anytime

    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn){
        _burnDSC(amountDscToBurn,msg.sender,msg.sender);//user is himself burning his dsc to increase health factor
        _revertIfHealthFactorIsBroken(msg.sender);//almost never needed
    }
    //user should get liquidated if value of DSC with user is less than collateral i.e if collateral goes below a certain threshold value
    //if certain person sees that collateral falls below a certain value then he can call this function to liquidate user
    //and the system rewards him 
    //@param collateral:The erc20 collateral token address to liquidate from user
    //@param user:user who has broken health factor 
    //@param debtToCover : amount of DSC needed to burn to improve user's health factor 
    //user can be partially liquidated 
    //liquidation bonus will be given for improving health factor
    //assumption : protocol is 200 percent overcollateralized 
    function liquidate(address collateral ,address user , uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered= getTokenAmountFromUsd(collateral,debtToCover);
        //liquidator is rewarded 10 percent
        //if user liquidates 100 dsc then he gets $110 worth of collateral
        uint256 bonusCollateral=(tokenAmountFromDebtCovered*LIQUIDATION_BONUS)/LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem=tokenAmountFromDebtCovered+bonusCollateral;
        _redeemCollateral(user,msg.sender,collateral,totalCollateralToRedeem);
        //now the dsc needs to be burnt which protocol recieved
        _burnDSC(debtToCover,user,msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor < startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        //we need to ensure that this liquidation doesn't break health factor of liquidator
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    function getHealthFactor() external view returns (uint256){
        return(_healthFactor(msg.sender));
    }
    //health factor is ratio of value of collateral to value of DSC
    //if a user goes below 1 they can get liquidated

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //price is in 8 decimals
        //price is the exchange rate of ETH/USD
        //ie If say 1ETH=1000USD then price=1000*10^8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION);
        /*
        latestRoundData() returns a tuple which includes 
        roundId (uint80):The ID of the round 
        answer (int256) — The latest price.
        startedAt (uint256) — Timestamp of when the round started.
        updatedAt (uint256) — Timestamp of when the round was updated.
        answeredInRound (uint80) — The round ID in which the answer was computed. 
        allows your contract to fetch real-time price data from Chainlink's decentralized oracles, 
        ensuring your contract can make decisions based on current market prices.*/
        //we only want the price and we are not interested in other things

        //if 1ETH=$1000 then returned value will be 1000*10^8
        //1000*1e8*1e10*1000/1e18 (amount is 1000)
    }
    function getTokenAmountFromUsd(address token,uint256 usdAmountInWei) public view returns (uint256){
        //We have 1 DAI=1USD
        //we have ETH/USD price feed i.e 1USD =...
        // (1/priceFeed)*USD price = ETH price
        //eg $100E18 USD debt   
        //1/pricefeed = 1/10^8=10^-8
        //100e18*

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
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
    //@param : from collateral removed from whose account
    //@param : to collateral given to whom 
    //note this collateral is given to liquidator so it won't be addred to s_collateralDeposited
    //this function is called usually when a user is liquidated
    function _redeemCollateral(address from , address to ,address tokenCollateralAddress,uint256 amountCollateral) internal moreThanZero(amountCollateral) nonReentrant {        
    //to redeemCollateral HF > 1 after collateral has been removed
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
            //automatically reverts in solidity
        emit CollateralRedeemed(from,to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        
    }
    //@param amountDscToBurn: The amount of DSC to burn
    //@param onBehalfOf: Whose dsc we are paying of 
    //@param dscFrom: where we are getting dsc from
    function _burnDSC (uint256 amountDscToBurn,address onBehalfOf,address dscFrom ) internal {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;//since with respect to protocol , the protocol is not lending dsc to the bad user 
        //so it is removed from his account , it is the same amount that liquidator deposits to pay off the bad user 
        //and the deposited tokens are then burnt
        bool success = i_dsc.transferFrom(dscFrom,address(this),amountDscToBurn);
        //user borrows dsc from protocol , gives collateral
        //user is then liquidated 
        //liquidator pays off user's debt , gets his collateral 
        //now since collateral is given away by the protocol
        //the protocol needs to burn the dsc tokens which they recieved from liquidator 
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);//burns from protocol's account
        _revertIfHealthFactorIsBroken(msg.sender);
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
        //value of collateral deposited/ value of DSC minted
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        //return (collateralValueInUsd/totalDscMinted); this returns float value
        //shld be always greater than 1 or maybe above a certain number greater than 1
        return(_calculateHealthFactor(totalDscMinted,collateralValueInUsd));
        //If the user's debt (in terms of the minted DSC) exceeds this adjusted collateral value, 
        //the user's position might be at risk of liquidation.
        //eg say 1000ETH deposited as collateral
        //1000 *50/100=500
        //therefore user can mint upto 500 DSC
        //healthFactor=500/totalDscMinted
        //HF>1 is safe therefore max value of DSC that can be minted is 500
        
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

    }
    function _calculateHealthFactor(uint256 totalDscMinted,uint256 collateralValueInUsd) internal pure returns (uint256){
        if(totalDscMinted==0){
            return type(uint256).max;//accounts for 0 health factor
        }
        uint256 collateralAdjustedForThreshHold=collateralValueInUsd*LIQUIDATION_THRESHOLD/LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshHold*PRECISION/totalDscMinted);
    }
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return(_getAccountInformation(user));
         }
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }
    function getCollateralBalanceOfUser(address user,address token) external view returns (uint256){
        return s_collateralDeposited[user][token];
    }
}

