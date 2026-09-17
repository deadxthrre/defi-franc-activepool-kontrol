// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/contracts/ActivePool.sol";
import {MockERC20, MockBorrowerOperations, MockTroveManager, MockTroveManagerHelpers, MockDefaultPool, MockCollSurplusPool, MockStabilityPool, MockStabilityPoolManager} from "./mocks/MockContracts.sol";

/// @notice Forge (fuzz) mirror of the Kontrol properties. Functions here are
///         `test`-prefixed so Forge executes them; they exercise the exact
///         same code paths as the `check_` Kontrol proofs.
///         This file is a *sanity harness*, not the verification artifact.
contract ActivePoolForgeSanityTest is Test {
    ActivePool internal ap;
    MockERC20 internal token;
    MockERC20 internal wbtc;
    MockBorrowerOperations internal bo;
    MockTroveManager internal tm;
    MockTroveManagerHelpers internal tmh;
    MockDefaultPool internal defaultPool;
    MockCollSurplusPool internal collSurplusPool;
    MockStabilityPool internal spETH;
    MockStabilityPool internal spWBTC;
    MockStabilityPoolManager internal spm;
    address internal alice;
    address constant ASSET_ETH = address(0);

    function setUp() public {
        ap = new ActivePool();
        token = new MockERC20();
        wbtc = new MockERC20();
        bo = new MockBorrowerOperations();
        tm = new MockTroveManager();
        tmh = new MockTroveManagerHelpers();
        defaultPool = new MockDefaultPool();
        collSurplusPool = new MockCollSurplusPool();
        spETH = new MockStabilityPool();
        spWBTC = new MockStabilityPool();
        spm = new MockStabilityPoolManager(address(this));
        alice = makeAddr("alice");

        spm.setStabilityPool(address(spETH), true);
        spm.setStabilityPool(address(spWBTC), true);
        spm.setAssetStabilityPool(ASSET_ETH, address(spETH));
        spm.setAssetStabilityPool(address(wbtc), address(spWBTC));

        ap.setAddresses(address(bo), address(tm), address(tmh), address(spm), address(defaultPool), address(collSurplusPool));
    }

    function test_external_attacker_cannot_send_eth(uint256 amount, address to) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));
        vm.assume(to != address(ap));
        vm.assume(to != address(spETH));
        vm.assume(to != address(spm));

        vm.deal(alice, amount);
        vm.prank(alice);
        vm.expectRevert("ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool");
        ap.sendAsset(ASSET_ETH, to, amount);
    }

    function test_external_attacker_cannot_send_erc20(uint256 amount, address to) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));
        vm.assume(to != address(ap));
        token.mint(address(ap), amount);

        vm.prank(alice);
        vm.expectRevert("ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool");
        ap.sendAsset(address(token), to, amount);
    }

    function test_sp_of_other_asset_cannot_drain(uint256 amount) public {
        vm.assume(amount > 0);
        wbtc.mint(address(ap), amount);
        vm.prank(address(spETH));
        vm.expectRevert();
        ap.sendAsset(address(wbtc), alice, amount);
    }

    function test_authorized_sp_eth_withdraw_decreases_balance(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 1e21);
        vm.deal(address(defaultPool), amount);
        vm.prank(address(defaultPool));
        (bool ok, ) = address(ap).call{value: amount}("");
        assertTrue(ok);

        assertEq(ap.getAssetBalance(ASSET_ETH), amount);
        vm.prank(address(spETH));
        ap.sendAsset(ASSET_ETH, address(spETH), amount);

        assertEq(ap.getAssetBalance(ASSET_ETH), 0);
        assertEq(address(spETH).balance, amount);
    }

    function testCannotSendMoreThanRecorded(uint256 deposited, uint256 attempted) public {
        vm.assume(deposited > 0 && deposited <= 1e21);
        vm.assume(attempted > deposited);
        vm.deal(address(defaultPool), deposited);
        vm.prank(address(defaultPool));
        (bool ok, ) = address(ap).call{value: deposited}("");
        assertTrue(ok);

        vm.prank(address(spETH));
        vm.expectRevert();
        ap.sendAsset(ASSET_ETH, alice, attempted);
    }
}