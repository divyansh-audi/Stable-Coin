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

// import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Divyansh
 *
 * The system is designed to be as minimal as possible ,and have the tokens maintain a 1 token==$1 peg.
 * The stablecoin has the proporties:
 * --Exogeneous Collateral
 * --Dollar Pegged
 * --Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance ,no fees,and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "overCollaterized",At no point ,should the value of all collateral <=backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC System .It handles all the logic for minTing and redeeming DSC ,as well as depositing & withdrawing collateral
 *
 * @notice This contract is very loosely based on the makerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////////////////
    //Errors                   //
    /////////////////////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToke();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HelathFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////////////
    //State Variables          //
    /////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    mapping(address token => address priceFeed) private s_priceFeed; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 ammount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //this means you need to be 200% overcollateralized.
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus.

    DecentralizedStableCoin private immutable i_DSC;

    /////////////////////////////
    //Events                   //
    /////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    /////////////////////////////
    //Modifier                 //
    /////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            //means equal to null
            revert DSCEngine__NotAllowedToke();
        }
        _;
    }

    /////////////////////////////
    //Functions                //
    /////////////////////////////

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        //USD Price Feed
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
        }
        //for example --ETH/USD,BTC/USD etc..
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeed[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_DSC = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////////
    //External Functions       //
    /////////////////////////////
    /**
     * @notice this function will deposit collateral and mint DSC in one function
     *
     * @param tokenCollateralAddress this is the address of weth or wbtc.
     * @param amountCollateral this is the amount of collateral you want to submit.
     * @param amountDscToMint this is the amount to stable coin which you want to mint.
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI -Checks,Effects,Interactions.
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */

    // If working with external contracts ,we should allow make it nonReentrant
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice This function burns DSC and redeems underlying collateral in one transaction .
     * @param tokenCollateralAddress the collateral address to redeem
     * @param amountCollateral amount of collateral to redeem
     * @param amountDSCToBurn amount of DSC to burn.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        burnDsc(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //reedem collateral al
    }

    //in order to reedem collateral:
    //1. health factor must be over one after the collateral pulled
    //DRY: Don't repeat yourself
    //CEI: Check,Effects,Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Threshold to let's say 150%
    // $100 ETH-->$74ETH
    // $50 DSC
    // Hey,if someone pays back your minted DSC ,they can have all your collateral for a discount.
    //so someone pay your 50 dsc and gets 74 eth and it was your punishment for letting your collateral undercollaterized.

    //check ig the collateral value>dsc amount ,Price Feeds

    /**
     * @notice follows CEI
     * @param amount :The amaount dsc to be mint
     * @notice they must have more collateral value than minimum threshold.
     */
    function mintDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        s_DSCMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_DSC.mint(msg.sender, amount);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender); //Don't think it will hit .
    }

    //$100 ETH backing 50$ dsc
    //$20 ETH back $50 DSC->DSC isnt worth 1$!!!
    // if someone is alomost undercollateralized, we will pay you to liquidate them !!

    /**
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function assumes that the protocol will be 200% overcollateeralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized,then we wouldn't be able to incentove the liquidated.
     * @param collateral The erc20 collateral address to liquidate from the user.
     * @param user user who was broken the health factor
     * @param debtTocover The amount of dsc you want to burn to improve user's health factor
     *
     * FOLLOW CEI-checks,effects,interactions.
     */
    function liquidate(address collateral, address user, uint256 debtTocover)
        external
        moreThanZero(debtTocover)
        nonReentrant
    {
        // need to check health factor of the user.
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HelathFactorOk();
        }
        //we want to burn their DSC "debt" and take their collateral.
        //Bad User:$140ETH ,$100 DSC
        // debt to cover =$100
        //$100 of DSC==???? ETH?
        uint256 tokenAmountfromDebtCovered = getTokenAmountFromUsd(collateral, debtTocover);
        //so msg.sender will pay the debt and get the 10% bonus from that
        // we should implement a feature to liquidate in the event the protocol is insolvent.
        // add sweep extra amounts into a treasury

        uint256 bonusCollateral = (tokenAmountfromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION);
        uint256 totalCollateralToReedeem = tokenAmountfromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToReedeem);
        _burnDsc(user, msg.sender, debtTocover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external {}

    ///////////////////////////////////////////
    //////PRIVATE AND INTERNAL FUNCTIONS///////
    ///////////////////////////////////////////
    /**
     * @dev low-level internal function ,do not call until the function calling it is checking for health factors being broken
     */
    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amount) private moreThanZero(amount) {
        s_DSCMinted[onBehalfOf] -= amount;
        bool success = i_DSC.transferFrom(dscFrom, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_DSC.burn(amount);
    }

    function _redeemCollateral(
        address from,
        address toAddress,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, toAddress, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(toAddress, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 coollateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        coollateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     * Returns how close to liquidation a user is
     * If the user goes below one ,they can be liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        //total DSC minted
        //total collateral VALLUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // return (coollateralValueInUsd/totalDscMinted);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;

        //example of this
        /**
         * Collateral value: $1000
         * Minted DSC (debt): $400
         * collateralAdjusted = (1000 * 50) / 100 = 500
         * healthFactor = (500 * 100) / 400 = 125
         * So the health factor is:
         *
         * 125 / 100 = 1.25 (safe)
         */
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health factor
        // 2. revert if not
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(healthFactor);
        }
    }

    /**
     *
     * Public And External View Functions*****
     *
     */
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalFunds) {
        //so currently how can you loop through and get the price ?? no way ,so you need to create an array which stores weth and wbtc for each

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            totalFunds += getUsdValue(s_collateralTokens[i], s_collateralDeposited[user][s_collateralTokens[i]]);
        }
        return totalFunds;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256 totalPrice) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //on the chainlink datafeed you can see this value has 8 decimal places
        //so 1ETH=$1000 ,the returned value from CL will be 1000*1e8
        uint256 unitPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
        totalPrice = unitPrice * amount / PRECISION;
    }

    function getTokenAmountFromUsd(address collateral, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[collateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        uint256 adjustedUsdPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
        return (usdAmountInWei * PRECISION / adjustedUsdPrice);
    }
}
