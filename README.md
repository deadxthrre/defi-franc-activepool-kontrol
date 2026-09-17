# Kontrol: DeFi Franc ActivePool Verification

Formal verification of the **DeFi Franc ActivePool** (`0x77E034c8A1392d99a2C776A6C1593866fEE36a33`, exact-match verified source, solc `0.8.14+commit.80d49f37`, optimizer 200 runs, evmVersion `london`) using **[Kontrol](https://github.com/runtimeverification/kontrol)** (Foundry integration for KEVM).

The goal is **permissionless fund-drain**: prove that no external actor can move assets out of the ActivePool, and that the pool's accounting invariants cannot be broken.

## Threat model

The ActivePool is the central custody contract of the DeFi Franc stablecoin system:

- It holds **all trove collateral** (ETH and ERC-20 assets).
- `sendAsset` is the **only** function that moves assets *out* of the pool.
- Cash/asset inflow is only via `receive()` (ETH) or `receivedERC20(...)`, both callable **only** by `BorrowerOperations` or `DefaultPool`.
- Outflow (`sendAsset`) is gated by `callerIsBOorTroveMorSP`: only `BorrowerOperations`, `TroveManager`, `TroveManagerHelpers`, or a **registered stability pool for the specific asset** may move assets.

A **fund-draining** bug means: (a) an unprivileged/external address can call `sendAsset`; (b) a stability pool registered for asset X can siphon asset Y; or (c) accounting (`assetsBalance`/`DCHFDebts`) diverges from actual holdings (e.g. send more than deposited, or deposit tracking off by one).

## Properties proved

| Property | Behaviour checked | Symbolic inputs |
|---|---|---|
| `check_external_attacker_cannot_send_eth` | Any fresh external `msg.sender` is rejected on `sendAsset(ETH,...)` | `uint256 amount`, `address to` |
| `check_external_attacker_cannot_send_erc20` | Any fresh external `msg.sender` is rejected on `sendAsset(ERC20,...)` | `uint256 amount`, `address to` |
| `check_sp_of_other_asset_cannot_drain` | An SP registered for ETH cannot move WBTC out of the pool | `uint256 amount` |
| `check_authorized_sp_eth_withdraw_decreases_balance_by_amount` | Authorized path: ETH only leaves after entry via `receive()`, and `assetsBalance[ETH]` decreases by exactly the amount (can never go negative) | `uint256 amount` |
| `check_cannot_send_more_than_recorded_balance` | Attempting to send more than recorded balance always reverts | `deposited`, `attempted` |
| `check_received_erc20_deposit_tracking` | ERC20 deposits from authorized `DefaultPool` are tracked exactly | `uint256 amount` |

Each property is a `check_*`-prefixed thunk so **Kontrol** symbolically executes it over *all* argument values (not just fuzzed ones). `test/ActivePoolForgeSanityTest.t.sol` is the same logic `check_*`-free so `forge test` can sanity-run it.

## Structure

```
src/contracts/ActivePool.sol        # exact verified source + deps (solc 0.8.14, run 200)
test/ActivePoolPropertiesTest.t.sol # Kontrol proof properties (check_*)
test/ActivePoolForgeSanityTest.t.sol# Forge-fuzzable twins of the properties
test/mocks/MockContracts.sol        # BorrowerOperations/TroveManager/SP/Pool mocks
.github/workflows/kontrol.yml       # GitHub Actions: build + prove, cached
```

## Running

Local (needs `kontrol` installed):
```sh
make check        # code style (runtimeverification conventions)
forge test        # fast sanity of the property logic (not the proofs)
make test-unit
kontrol build
kontrol prove --match-test 'ActivePoolPropertiesTest' --reinit
```

CI (this repo's GitHub Action): runs `kontrol build` then `kontrol prove` for the three property groups; cached build artifacts shorten re-runs. Results are uploaded as the `kontrol-reports` artifact.

## Notes / caveats

- **Verified-source fidelity**: the contract source was pulled from Sourcify/`metadata.json` with `creationMatch+runtimeMatch = exact_match` on-chain (byte-identical). Compilation settings match the deployment metadata (`0.8.14`, optimizer 200, `london`), so properties are proven against the **actual deployed logic**, modulo the locked-in proxy implementation (`0xda2213e...` in the Donkey case — this file targets the DeFi Franc ActivePool directly, which is *not* a proxy).
- **Contract-scope proofs**: the system-level call graph (Controller/price oracle) is out of scope; these properties verify ActivePool in isolation with mock dependents, per the Kontrol recommended pattern.
- Properties prove **absence of the specified drain categories** — not absence of all possible vulnerabilities.

## License

BSD-3-Clause (contracts per their own DeFi Franc / MIT license).