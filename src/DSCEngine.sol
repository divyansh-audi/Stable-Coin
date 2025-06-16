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
 * @notice This contract is the core of the DSC System .It handles all the logic for mining and redeeming DSC ,as well as depositing & withdrawing collateral
 *
 * @notice This contract is very loosely based on the makerDAO (DAI) system.
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
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin private immutable i_DSC;

    /////////////////////////////
    //Events                   //
    /////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
        for (uint256 i = 0; i <= tokenAddress.length; i++) {
            s_priceFeed[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_DSC = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////////
    //External Functions       //
    /////////////////////////////

    function depositCollateralAndMintDSC() external {}

    /**
     * @notice follows CEI -Checks,Effects,Interactions.
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

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
    function mintDsc(uint256 amount) external moreThanZero(amount) nonReentrant {
        s_DSCMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_DSC.mint(msg.sender, amount);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

    /**
     *
     * Private And Internal Functions*****
     *
     */
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

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //on the chainlink datafeed you can see this value has 8 decimal places
        //so 1ETH=$1000 ,the returned value from CL will be 1000*1e8
        uint256 unitPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
        uint256 totalPrice = unitPrice * amount / PRECISION;
        return totalPrice;
    }
}
