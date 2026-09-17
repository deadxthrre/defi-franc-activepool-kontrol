// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/contracts/ActivePool.sol";
import "../src/contracts/Interfaces/IStabilityPoolManager.sol";
import {MockERC20, MockBorrowerOperations, MockTroveManager, MockTroveManagerHelpers, MockDefaultPool, MockCollSurplusPool, MockStabilityPool, MockStabilityPoolManager} from "./mocks/MockContracts.sol";

/// @notice Property suite for the DeFi Franc ActivePool (0x77E034c8...36a33),
///         targeting permissionless fund-drain by an external attacker.
///
/// Threat model: the ActivePool is the only contract that holds trove collateral
/// and is the *only* path that moves assets OUT of the system (sendAsset).
/// A drain means: any msg.sender NOT in {borrowerOperations, troveManager,
/// troveManagerHelpers, a stability pool registered for THIS asset} moving assets
/// out, or an asset-accounting mismatch that lets one market steal another's.
///
/// Every property below is written as a Kontrol `prove`-prefixed or `check`-
/// prefixed test so symbolic execution explores ALL values of every argument.
contract ActivePoolPropertiesTest is Test {
    ActivePool internal ap;
    MockERC20 internal token;
    MockBorrowerOperations internal bo;
    MockTroveManager internal tm;
    MockTroveManagerHelpers internal tmh;
    MockDefaultPool internal defaultPool;
    MockCollSurplusPool internal collSurplusPool;
    MockStabilityPool internal spETH;
    MockStabilityPool internal spWBTC;
    MockStabilityPoolManager internal spm;

    address constant ASSET_ETH = address(0);
    MockERC20 internal wbtc;
    address internal alice;

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

        ap.setAddresses(
            address(bo),
            address(tm),
            address(tmh),
            address(spm),
            address(defaultPool),
            address(collSurplusPool)
        );
    }

    // ------------------------------------------------------------------
    // 1. Permissionless drain: sendAsset is the ONLY out-flow. Any caller
    //    other than the four authorized roles must be rejected.
    // ------------------------------------------------------------------

    /// @notice A completely external fresh address cannot send ETH out.
    function check_external_attacker_cannot_send_eth(uint256 amount, address to) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));
        vm.assume(to != address(ap));
        vm.assume(to != address(spETH));
        vm.assume(to != address(spWBTC));
        vm.assume(to != address(spm));

        vm.deal(alice, amount);
        vm.prank(alice);

        vm.expectRevert("ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool");
        ap.sendAsset(ASSET_ETH, to, amount);
    }

    /// @notice External attacker cannot send ERC20 out either.
    function check_external_attacker_cannot_send_erc20(uint256 amount, address to) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));
        vm.assume(to != address(ap));
        token.mint(address(ap), amount);

        vm.prank(alice);
        vm.expectRevert("ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool");
        ap.sendAsset(address(token), to, amount);
    }

    /// @notice A stability pool registered for asset X must NOT be able to raid
    ///         the collateral of a different asset Y (cross-asset drain).
    function check_sp_of_other_asset_cannot_drain(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);
        wbtc.mint(address(ap), type(uint128).max + 1);

        // spETH is registered for ETH, not for wbtc.
        vm.prank(address(spETH));
        vm.expectRevert();
        ap.sendAsset(address(wbtc), alice, amount);
    }

    // ------------------------------------------------------------------
    // 2. Authorized flows keep accounting sound.
    // ------------------------------------------------------------------

    /// @notice A registered SP for THIS asset can withdraw (authorized path),
    ///         and accounting decreases exactly by the amount withdrawn.
    ///         The pool can only ever send out what was recorded as deposited.
    function check_authorized_sp_eth_withdraw_decreases_balance_by_amount(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 1e21);

        // Seed the accounting via the ONLY allowed entry: receive() called by
        // an authorized depositor (defaultPool). This mirrors real usage where
        // collateral enters the ActivePool before it can leave.
        vm.deal(address(defaultPool), amount);
        vm.prank(address(defaultPool));
        (bool ok, ) = address(ap).call{value: amount}("");
        assertTrue(ok, "ETH deposit rejected");

        uint256 before = ap.getAssetBalance(ASSET_ETH);
        assertEq(before, amount);

        vm.prank(address(spETH));
        ap.sendAsset(ASSET_ETH, address(spETH), amount);

        uint256 balance_after = ap.getAssetBalance(ASSET_ETH);
        assertEq(balance_after, 0);
        assertEq(address(spETH).balance, amount);
    }

    /// @notice Draining more than the recorded balance must always revert:
    ///         accounting cannot go negative even for authorized callers.
    function check_cannot_send_more_than_recorded_balance(uint256 deposited, uint256 attempted) public {
        vm.assume(deposited > 0);
        vm.assume(deposited <= 1e21);
        vm.assume(attempted > deposited);

        vm.deal(address(defaultPool), deposited);
        vm.prank(address(defaultPool));
        (bool ok, ) = address(ap).call{value: deposited}("");
        assertTrue(ok);

        vm.prank(address(spETH));
        vm.expectRevert();
        ap.sendAsset(ASSET_ETH, alice, attempted);
    }

    /// @notice accounting: sum of receivedERC20 deposits must be reflected.
    function check_received_erc20_deposit_tracking(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        token.mint(address(this), amount);
        token.approve(address(ap), amount);
        vm.prank(address(defaultPool));
        ap.receivedERC20(address(token), amount);

        assertEq(ap.getAssetBalance(address(token)), amount);
    }
}