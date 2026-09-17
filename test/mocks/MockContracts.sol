// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "../../src/contracts/Interfaces/IStabilityPoolManager.sol";
import "../../src/contracts/Interfaces/IStabilityPool.sol";
import "../../src/contracts/Interfaces/IDefaultPool.sol";
import "../../src/contracts/Interfaces/ICollSurplusPool.sol";
import "../../src/contracts/Interfaces/IDeposit.sol";
import "../../src/contracts/Interfaces/IPool.sol";

/// @notice Minimal ERC20 used as the "asset" in the pool tests.
contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MOCK: insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "MOCK: allowance");
        require(balanceOf[from] >= amount, "MOCK: insufficient");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice BorrowOperations stand-in: authorized to drive the pool forward.
contract MockBorrowerOperations {
    function batchDeposit(IPool pool, address asset, uint256 amount) external payable {
        pool.receivedERC20(asset, amount);
    }

    function batchWithdraw(IPool pool, address asset, address to, uint256 amount) external {
        // interface has no holder-account; direct send via the shared pool API
        // is only reachable through ActivePool.sendAsset for mocks, so instead
        // funnel through the ActivePool's own sendAsset path via the IPool view.
        (bool ok, ) = address(pool).call(abi.encodeWithSignature("sendAsset(address,address,uint256)", asset, to, amount));
        require(ok, "BO batchWithdraw failed");
    }
}

/// @notice TroveManager stand-in (authorized caller).
contract MockTroveManager {}

/// @notice TroveManagerHelpers stand-in (authorized caller).
contract MockTroveManagerHelpers {}

/// @notice DefaultPool stand-in, implements IDeposit + IPool views.
contract MockDefaultPool is IDefaultPool {
    mapping(address => uint256) public _assetBalance;
    mapping(address => uint256) public _dchfDebt;

    receive() external payable {}

    function receivedERC20(address _asset, uint256 _amount) external override {
        _assetBalance[_asset] += _amount;
    }

    function getAssetBalance(address _asset) external view override returns (uint256) {
        return _assetBalance[_asset];
    }

    function getDCHFDebt(address _asset) external view override returns (uint256) {
        return _dchfDebt[_asset];
    }

    function increaseDCHFDebt(address _asset, uint256 _amount) external override {
        _dchfDebt[_asset] += _amount;
    }

    function decreaseDCHFDebt(address _asset, uint256 _amount) external override {
        _dchfDebt[_asset] -= _amount;
    }

    function sendAssetToActivePool(address _asset, uint256 _amount) external override {}
}

/// @notice CollSurplusPool stand-in (implements IDeposit).
contract MockCollSurplusPool is IDeposit {
    mapping(address => uint256) public _surplus;
    mapping(address => mapping(address => uint256)) public _coll;

    receive() external payable {}

    function receivedERC20(address _asset, uint256 _amount) external override {
        _surplus[_asset] += _amount;
    }

    function getAssetBalance(address _asset) external view returns (uint256) {
        return _surplus[_asset];
    }
}

/// @notice StabilityPool stand-in (only IDeposit + payable, all ActivePool needs).
contract MockStabilityPool is IDeposit {
    receive() external payable {}

    function receivedERC20(address _asset, uint256 _amount) external override {
        // ActivePool only requires the IDeposit callback to be callable.
        _asset; _amount;
    }

    function getAssetBalance(address _asset) external view returns (uint256) {
        (_asset);
        return 0;
    }
}

/// @notice Configurable StabilityPoolManager stand-in — the trust boundary that
///         decides "is this caller a registered stability pool?".
contract MockStabilityPoolManager is IStabilityPoolManager {
    mapping(address => bool) public registeredSP;
    mapping(address => address) public assetSP; // asset -> stability pool
    address public ADMIN;

    constructor(address admin_) {
        ADMIN = admin_;
    }

    function setStabilityPool(address sp, bool registered) external {
        require(msg.sender == ADMIN, "admin only");
        registeredSP[sp] = registered;
    }

    function setAssetStabilityPool(address asset, address sp) external {
        require(msg.sender == ADMIN, "admin only");
        assetSP[asset] = sp;
    }

    function isStabilityPool(address stabilityPool) external view override returns (bool) {
        return registeredSP[stabilityPool];
    }

    function addStabilityPool(address asset, address stabilityPool) external override {
        require(msg.sender == ADMIN, "admin only");
        registeredSP[stabilityPool] = true;
        assetSP[asset] = stabilityPool;
    }

    function getAssetStabilityPool(address asset) external view override returns (IStabilityPool) {
        return IStabilityPool(assetSP[asset]);
    }

    function unsafeGetAssetStabilityPool(address asset) external view override returns (address) {
        return assetSP[asset];
    }
}