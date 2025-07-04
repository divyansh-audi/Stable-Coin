//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDecentralizedStableCoin} from "script/DeployDecentralizedStableCoin.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin public stableCoin;
    DeployDecentralizedStableCoin public deployer;
    address public USER = makeAddr("USER");
    uint256 public constant STARTING_PRICE = 100 ether;
    address owner;

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
        stableCoin = deployer.run();
        owner = stableCoin.owner();
    }

    function testMintFunctionIsOnlyTriggeredByOwner() public {
        vm.prank(owner);
        bool success = stableCoin.mint(USER, 10 ether);
        assertEq(success, true);
    }

    function testTokensAreGettingMinted() public {
        vm.prank(owner);
        stableCoin.mint(USER, 10 ether);
        uint256 balance = stableCoin.balanceOf(USER);
        assertEq(balance, 10 ether);
        uint256 ownerBalance = stableCoin.balanceOf(owner);
        uint256 contractBalance = stableCoin.balanceOf(address(this));
        // console.log("Contract Balance", contractBalance);// foundry comes with a default address balance in the contract so that we can test freely :)
        assertEq(ownerBalance, 0);
        assertEq(contractBalance, 0);
    }

    function testMintFunctionRevertsWithZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        stableCoin.mint(USER, 0);
    }

    function testBurnFunctionIsBurningTokens() public {
        vm.startPrank(owner);
        stableCoin.mint(USER, 10 ether);
        stableCoin.mint(owner, 10 ether);
        stableCoin.burn(5 ether);
        vm.stopPrank();
        uint256 ownerBalance = stableCoin.balanceOf(owner);
        assertEq(ownerBalance, 5 ether);
    }

    function testBurnFuntionRevertsIfOwnerHasLessToken() public {
        vm.startPrank(owner);
        stableCoin.mint(USER, 10 ether);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        stableCoin.burn(5 ether);
        vm.stopPrank();
    }
}
