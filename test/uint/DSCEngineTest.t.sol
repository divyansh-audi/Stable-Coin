// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deploy;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address wbtc;
    address btcUsdPriceFeed;
    address defaultOwner;
    uint256 deployerKey;
    address public USER = makeAddr("USER");
    address public LIQUADATOR = makeAddr("LIQUIDATOR");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 50 ether;

    function setUp() public {
        deploy = new DeployDSC();
        (dscEngine, dsc, config) = deploy.run();
        (defaultOwner, weth, wbtc, ethUsdPriceFeed, btcUsdPriceFeed, deployerKey) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    ///////////////////////////////
    ////CONSTRUCTOR TEST        ///
    ///////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testConstructorIsWorkingFine() public {
        DSCEngine dscNewEngine;
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.prank(USER);
        dscNewEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        assert(dscEngine.getImmutableDSC() == DecentralizedStableCoin(dsc));
        assert(dscNewEngine.getImmutableDSC() == DecentralizedStableCoin(dsc));
        assert(dscNewEngine.getPriceFeed(weth) == ethUsdPriceFeed);
        assert(dscNewEngine.getPriceFeed(wbtc) == btcUsdPriceFeed);
        assert(dscNewEngine.getCollateralTokenArray()[0] == weth);
        assert(dscNewEngine.getCollateralTokenArray()[1] == wbtc);
    }

    function testConstructorReverts() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }
    /////////////////////////
    ////PRICE TEST        ///
    /////////////////////////

    function testPriceFeedWorkingFine() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);

        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmountInWei = 2000 ether;
        uint256 expectedValueOfEther = 1 ether;
        uint256 actualOutcome = dscEngine.getTokenAmountFromUsd(weth, usdAmountInWei);
        assert(expectedValueOfEther == actualOutcome);
    }

    //////////////////////////////////////
    ////DEPOSIT COLLATERAL TEST        ///
    //////////////////////////////////////
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertWhenInvalidToken() public {
        ERC20Mock wrandom = new ERC20Mock();
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToke.selector);
        dscEngine.depositCollateral(address(wrandom), 10 ether);
    }

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralIsEmitingCorrectly() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dscEngine));
        emit CollateralDeposited(USER, weth, 1 ether);

        dscEngine.depositCollateral(weth, 1 ether);
        vm.stopPrank();
        (, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        assert(collateralValueInUsd == 2000 ether);
    }

    ////////////////////////////////////////////
    ///////MINT DSC TEST////////////////////////
    ////////////////////////////////////////////

    function testMintDscRevertsIfCollateralIsNotDeposited() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, 0));
        dscEngine.mintDsc(1 ether);
    }

    function testMintDscEdgeCaseForHealthFactor() public depositedCollateral {
        vm.prank(USER);
        dscEngine.mintDsc((AMOUNT_COLLATERAL * 2000 / 2) - 1);
        uint256 expectedDscMinted = (AMOUNT_COLLATERAL * 2000 / 2) - 1;
        uint256 actualDscMinted = dscEngine.getDscAmountMinted(USER);
        assert(expectedDscMinted == actualDscMinted);
    }

    function testRevertMintDscEdgeCaseForHealthFactor() public depositedCollateral {
        uint256 expectedHealthFactor =
            (((AMOUNT_COLLATERAL * 2000 * 50) / 100) * 1e18) / (((AMOUNT_COLLATERAL * 2000) / 2) + 1);
        console.log(expectedHealthFactor);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDsc(((AMOUNT_COLLATERAL * 2000) / 2) + 1);
    }

    /////////////////////////////////////////////////
    ////////DEPOSIT COLLATERAL AND MINT DSC//////////
    /////////////////////////////////////////////////
    function testDepositCollateralAndMintDSC() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, (AMOUNT_COLLATERAL * 2000) / 2);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        DecentralizedStableCoin dscfromAddress = dscEngine.getImmutableDSC();
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assert(totalDscMinted == AMOUNT_COLLATERAL * 1000);
        assert(collateralValueInUsd == AMOUNT_COLLATERAL * 2000);
        assert(dscfromAddress == DecentralizedStableCoin(dsc));
        assert(healthFactor == 1 ether);
    }

    /////////////////////////////////////////////////
    //////REEDEM COLLATERAL /////////////////////////
    /////////////////////////////////////////////////

    modifier collateralDepositedAndDscMinted() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); // this function is approving the dscEngine that it can spend AMOUNT_COLLATERAL when calling transferFrom function.
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, 4 ether * 2000);
        vm.stopPrank();
        _;
    }

    function testRedeemCollateralRevertsWithoutDepositingCollateral() public {
        vm.startPrank(USER);
        // ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        // vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, 0));
        // we cant do this as--->s_collateralDeposited[msg.sender][token] -= amount; //this is making the value 0-(1 ether) which is making it negative

        vm.expectRevert();
        dscEngine.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
        // vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, 0));
    }

    function testRedeemCollateralRevertsDueToHeathFactorBroken() public collateralDepositedAndDscMinted {
        uint256 collateralDeposited = AMOUNT_COLLATERAL;
        uint256 dscMintedValueInEther = 4 ether;
        uint256 collateralRedeem = 3 ether;
        uint256 healthFactorAfterRedeeming =
            (((collateralDeposited - collateralRedeem) / 2) * 1e18) / dscMintedValueInEther;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, healthFactorAfterRedeeming)
        );
        dscEngine.redeemCollateral(weth, collateralRedeem);
        // assert(healthFactorAfterRedeeming == dscEngine.getHealthFactor(USER));
    }

    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function testRedeemCollateralIsEmittingStuff() public collateralDepositedAndDscMinted {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false);

        emit CollateralRedeemed(USER, USER, weth, 1e18);
        dscEngine.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
        assert(dscEngine.getCollateralDeposited(USER, weth) == 9 ether);
    }
    /////////////////////////////////////////////////
    //////BURN DSC          /////////////////////////
    /////////////////////////////////////////////////

    function testBurnDscRevertsWithoutMintingDsc() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(1 ether * 2000);
    }

    // this function wont ever be going to liquidate you .
    function testBurnDsc() public collateralDepositedAndDscMinted {
        uint256 healthFactorBeforeBurning = dscEngine.getHealthFactor(USER);
        vm.startPrank(USER);
        // ERC20Mock(weth).allowance(USER, address(dscEngine));
        dsc.approve(address(dscEngine), dsc.balanceOf(USER)); // this is telling that dscEngine you can spend this much dsc from Caller of this function
        console.log("Balance of USER is :", dsc.balanceOf(USER));
        dscEngine.burnDsc(1 ether * 2000);
        vm.stopPrank();

        uint256 healthFactorAfterBurning = dscEngine.getHealthFactor(USER);

        assert(dscEngine.getDscAmountMinted(USER) == 3 ether * 2000);
        assert(healthFactorBeforeBurning < healthFactorAfterBurning);
        assert(dsc.balanceOf(USER) == 3 ether * 2000);
    }

    /////////////////////////////////////////////////
    //////BURN DSC AND REDEEM COLLATERAL/////////////
    /////////////////////////////////////////////////
    function testRedeemCollateralForDsc() public collateralDepositedAndDscMinted {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), dsc.balanceOf(USER));
        dscEngine.redeemCollateralForDsc(weth, 4 ether, 2000 * 1 ether);

        vm.stopPrank();
        assert(dscEngine.getHealthFactor(USER) == 1e18);
    }
    //////////////////////////////////////////
    //////LIQUIDATE              /////////////
    //////////////////////////////////////////

    modifier collateralDepositedMintedAndApproved() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); // this function is approving the dscEngine that it can spend AMOUNT_COLLATERAL when calling transferFrom function.
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, 4 ether * 2000);
        dsc.approve(address(dscEngine), 4 * 2000 ether);
        vm.stopPrank();
        _;
    }

    function testLiquidateRevertIfHealthFactorIsGood() public collateralDepositedMintedAndApproved {
        vm.startPrank(LIQUADATOR);
        console.log("health factor of USER is :", dscEngine.getHealthFactor(USER));
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        // vm.expectRevert();
        dscEngine.liquidate(weth, USER, 4 ether * 2000);
        console.log("balance of USER is", dsc.balanceOf(USER));
        vm.stopPrank();
    }

    function testLiquidationRevertsWhenHealthFactorStillLow() public collateralDepositedMintedAndApproved {
        vm.startPrank(USER);

        dscEngine.getReedemCollateral(USER, USER, weth, 4 ether);
        vm.expectRevert();
        dscEngine.liquidate(weth, USER, 1 ether * 2000);
        vm.stopPrank();
    }
}
