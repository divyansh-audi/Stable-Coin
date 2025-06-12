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

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

contract DSCEngine {
    function depositCollateralAndMintDSC() external {}

    function depositCollateral() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    // Threshold to let's say 150%
    // $100 ETH-->$74ETH
    // $50 DSC
    // Hey,if someone pays back your minted DSC ,they can have all your collateral for a discount.
    //so someone pay your 50 dsc and gets 74 eth and it was your punishment for letting your collateral undercollaterized.
    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}
}
