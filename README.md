<<<<<<< HEAD
# Rumor Contracts

DeFi protocol for automated yield farming on Polygon using proxy accounts with shared strategy execution.

## Overview

Rumor Contracts enables users to deploy individual proxy contracts that execute shared investment strategies across Aave V3 and Uniswap V3. Each user owns their proxy account while benefiting from a shared strategy executor that splits USDT investments 50/50 between Aave USDT and USDC lending pools.

## Architecture

### Core Contracts

- **`ProxyAccount.sol`** - User-owned contract for token management and strategy execution
  - Owner-only access control
  - Meta-transaction support (EIP-712)
  - Fee collection (0.1% default)
  - Integration with Aave V3 and Uniswap V3

- **`ProxyFactory.sol`** - Factory for deploying standardized proxy accounts
  - One proxy per user
  - Immutable protocol configuration

- **`StrategyExecutor.sol`** - Shared strategy implementation
  - Splits USDT 50/50
  - Deposits 50% to Aave USDT pool (receives aUSDT)
  - Swaps remaining 50% to USDC via Uniswap V3
  - Deposits USDC to Aave (receives aUSDC)
  - Slippage protection: 0.5%

- **`LendingStrategy.sol`** - Abstract interface for strategies

## Protocol Addresses (Polygon)

```
USDT:        0xc2132D05D31c914a87C6611C10748AEb04B58e8F
USDC:        0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
aUSDT:       0x6ab707Aca953eDAeFBc4fD23bA73294241490620
aUSDC:       0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD
Aave Pool:   0x794a61358D6845594F94dc1DB02A252b5b4814aD
Uniswap V3:  0xE592427A0AEce92De3Edee1F18E0157C05861564
```

## Installation

```bash
forge install
```

## Build

```bash
forge build
```

## Test

```bash
forge test
```

For mainnet fork testing:
```bash
forge test --fork-url https://polygon-rpc.com
```

## Deploy

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url <polygon_rpc_url> --private-key <private_key> --broadcast
```
=======
<img width="1577" height="600" alt="rumor-git-header" src="https://github.com/user-attachments/assets/4e9acc55-8748-41f2-843f-7239e07cea51" />
<br>
<br>

<h3>TL;DR</h3>
<p>
  <strong>Rumor</strong> is a no-code DeFi strategy builder that turns complex, multi-step crypto
  workflows into <strong>one-click, non-custodial</strong> actions. Users design strategies visually
  while Rumor compiles them into a <strong>deterministic plan</strong> and executes with guardrails.
  Bridges, routing, gas and multi-chain sequencing are abstracted away. The UX targets <strong>gasless
  usage</strong> via ERC-4337 <em>(pay in stablecoins)</em>, and emphasizes <strong>security, transparency, and auditability</strong>.
</p>
<br>

<h3>- why rumor</h3>
<p>
  DeFi is powerful yet fragmented: many chains and UIs, approvals, bridging friction, native-gas
  hurdles, MEV/slippage risk, and opaque, error-prone flows. Most people don’t have the time or
  expertise to stitch this together safely. <strong>Rumor abstracts the complexity without taking custody</strong>,
  preserves user ownership, and makes execution verifiable end-to-end.
</p>
<br>

<h3>- vision</h3>
<p>
  <strong>No-code visual builder.</strong> Create strategies from blocks such as Swap, Lend/Borrow, LP, Stake, Bridge,
  Claim, Wrap/Unwrap, Permit. The result is serialized into a canonical JSON/DAG and bound on-chain by a plan hash.
</p>
<p>
  <strong>One-click, chain-abstracted UX.</strong> Rumor plans, sequences and bridges across networks automatically so the user
  never handles chain switching, approvals per step, or gas on the target chain.
</p>
<p>
  <strong>Non-custodial by design.</strong> Funds live in user-owned smart accounts with direct escape hatches; Rumor never
  takes custody.
</p>
<p>
  <strong>Gasless experience.</strong> ERC-4337 + Token Paymaster aims for stablecoin-denominated fees; users avoid
  “you need native gas on chain X”.
</p>
<p>
  <strong>Unified Withdraw.</strong> Unwind multi-chain positions back to a target asset/chain in a single action with
  clear status and partial-completion handling.
</p>
<p>
  <strong>Progressive risk disclosure.</strong> Green / Amber / Red profiles with caps, quizzes and explicit acknowledgements.
</p>
<br>

<h3>- rumor enables</h3>
<p>
  One-click base strategies <em>(lend, LP, stake)</em> with clear estimates and guardrails; yield rotation and rebalancing
  across protocols and chains; auto-compound and schedulers with minimum gain thresholds; cross-chain operations
  <em>(bridge → swap → deploy)</em> managed as one plan; private strategies that reveal only a plan hash while keeping the
  JSON off-chain with access control.
</p>
<br>

<h3>- design principles</h3>
  <p><strong>Security-first & minimal trust.</strong> Immutable user accounts, protocol allow-lists, scoped pauses and audited adapters.  </p>
  <p><strong>Modularity & extensibility.</strong> A unified adapter interface and registries enable safe onboarding of protocols with risk tags.</p>
  <p><strong>Exactly-once semantics.</strong> Idempotent inbox/outbox with GUIDs and nonces, double-ACK transport checks, and <em>saga-style</em> compensations.</p>
  <p><strong>MEV-aware execution.</strong> Deadlines, minOut, pre-simulation, private relays for sensitive steps, and re-validation at destination.</p>
  <p><strong>Progressive decentralization.</strong> Clear path from multisig+timelock toward on-chain governance.</p>
<br>
>>>>>>> 7151c617d10fa5b787225bb1692e937ad1cc4b99

<h2> High-Level Architecture</h2>

<<<<<<< HEAD
### 1. Create Proxy Account

```solidity
address proxy = proxyFactory.createProxy();
```

### 2. Execute Strategy

```solidity
// Approve USDT to proxy
IERC20(USDT).approve(proxy, amount);

// Execute strategy
ProxyAccount(proxy).runStrategy(address(0), amount); // address(0) uses default strategy
```

### 3. Claim Yields

```solidity
// Withdraws from Aave, swaps USDC to USDT, transfers to owner
ProxyAccount(proxy).claim();
```

## Features

- **Gas Efficient**: Shared strategy executor reduces deployment costs
- **Owner Control**: Full ownership of individual proxy accounts
- **Meta-transactions**: Gasless operation support
- **Security**: ReentrancyGuard, owner-only access, slippage protection
- **Multicall**: Batch operations in single transaction

## Fee Structure

- Strategy fee: 0.1% (10 basis points)
- Fee recipient: Configurable at deployment
- Fee deducted before strategy execution

## Technical Stack

- **Solidity**: ^0.8.20
- **Framework**: Foundry
- **Dependencies**: OpenZeppelin Contracts, Forge Std
- **Network**: Polygon Mainnet

## License

MIT
=======
<figure>
  <img width="5412" height="4316" alt="rumor-is" src="https://github.com/user-attachments/assets/9aee31a8-1fde-4030-9921-6606e98bed8f" />
  <figcaption>
    <em>
    User plane <em>(Web App, API/BFF, Visual Builder)</em> → Orchestration <em>(Intent Resolver / Tx-Manager, Cross-chain Orchestrator,
    Strategy Storage, Route &amp; Gas Quoter)</em> → Data <em>(Indexer &amp; Portfolio, Observability)</em> → On-chain per chain
    <em>(ProxyFactory, ProxyAccount, StrategyExecutor <em>(Diamond)</em>, Adapter &amp; Risk registries, Token Paymaster)</em> +
    external bridges/messaging, price oracles, AA Bundler/EntryPoint, IPFS/Arweave. </em>  
  </figcaption>
</figure>
<br>
<br>

<h3>- on-chain components <em>(Overview)</em></h3>

<h4>ProxyFactory &amp; ProxyAccount <em>(per user, per chain)</em></h4>
<p>
  Minimal, non-upgradeable smart accounts holding user funds. Authorization via owner/multisig and an executor allow-list.
  Idempotent message intake and reentrancy protection. Direct withdrawal <em>(escape hatch)</em> keeps users in control even under
  degraded conditions.
</p>

<h4>StrategyExecutor <em>(EIP-2535 Diamond)</em></h4>
<p>
  A shared per-chain executor with facets such as <em>Swap</em>, <em>LendBorrow</em>, <em>StakeReward</em>, <em>Bridge</em>, <em>Admin</em>.
  Centralized parameter validation <em>(slippage, deadlines, price sanity)</em> and hardened external calls <em>(gas caps, return-data checks)</em>.
  Facet-level pausing enables fine-grained safety responses.
</p>

<h4>Adapter Layer &amp; Registries</h4>
<p>
  Thin adapters implement a common interface for quotes and calldata construction. The Adapter Registry stores addresses,
  versions and audit tags; the Risk Config sets TVL caps, slippage ceilings and per-protocol/chain limits. Version quarantine,
  canary rollout and security sentinels reduce integration risk.
</p>

<h4>Token Paymaster <em>(ERC-4337)</em></h4>
<p>
  Sponsored gas in stablecoins with quotas and TTLs. Accounting-only <code>postOp</code> and a reserve-on-start with final
  true-up settlement policy minimize UX friction while bounding platform risk.
</p>
<br>

<h3>- off-chain &amp; orchestration <em>(Overview)</em></h3>

<h4>Intent Resolver / Tx-Manager.</h4>
<p>
  Compiles the visual graph into a deterministic plan and materializes
  route/bridge choices before the first on-chain step.
</p>

<h4>Cross-chain Orchestrator.</h4>
<p>
  Sequences dependent steps and parallelizes independent ones; tracks GUID/planHash/stepIdx,
  retries/timeouts and performs <em>saga</em> compensations on failure.
</p>

<h4>Route &amp; Gas Quoter.</h4>
<p>
  Quotes with TTL, deadlines and minOut; MEV-aware routing with private relays where needed.
</p>

<h4>Strategy Storage Gateway.</h4>
<p>
  Plan JSON on IPFS <em>(optional Arweave backup)</em>; on-chain binding via plan hash; optional encryption/ACL.
</p>

<h4>Indexer &amp; Portfolio.</h4>
<p>
  Cross-chain correlation of events and aggregation of balances/positions; pending remainders and
  execution state surfaced to the UI. Observability monitors SLOs <em>(T99 by class)</em>, stuck-age thresholds, paymaster spend, bridge/DVN health
  and oracle heartbeat/deviation.
</p>

<h4>Safety &amp; Risk Controls</h4>
<p>
  Risk profiles and caps per user/strategy/chain; per-protocol/chain TVL limits and global ceilings. Oracle policy with primary/secondary feeds,
  max age and deviation bounds <em>(short TWAP where applicable)</em>. Bridge security with route allow-lists, per-tx caps, split-routing for size tiers,
  stuck-age auto-pauses and provider diversification. Scoped circuit breakers <em>(ERC-7265-like)</em> allow pausing by scope <em>(global / chain / protocol / asset / selector)</em>.
  Unified Withdraw and direct ProxyAccount withdrawals remain available under incident response.
</p>
<br>

<h3>- roadmap <em>(Phased)</em></h3>
<p>
  <strong>P0 - Single-chain foundation:</strong> proxy accounts, shared Diamond executor, Aave/Uniswap adapters, demo 50/50 strategy. <em>(Already finished)</em><br/>
  <strong>P1 - Multi-strategy <em>(single chain)</em>:</strong> adapter expansion <em>(10–20 blue-chips)</em>, AA/Paymaster UX hardening, simulation/quoting.<br/>
  <strong>P2 - Cross-chain MVP <em>(2–3 chains)</em>:</strong> messaging adapter with failover, bridge policy, settlement on funding chain, observability/alerts.<br/>
  <strong>P3 - Visual Builder <em>(Manual/Assisted)</em>:</strong> deterministic serialization and marketplace-ready strategy templates.<br/>
  <strong>P4 - Scale-out &amp; Governance:</strong> more chains/protocols, audits/bug bounty, Safe+Timelock → Governor.
</p>
<br>

<h3>- status &amp; demo</h3>

  <p><strong>Today:</strong> production-ready demo on mainnet <em>(current MVP runs on Polygon with Aave v3 &amp; Uniswap v3 integration)</em>, shared executor and per-user proxies.</p>
  <p><strong>Try it live:</strong> <a href="https://rumor.fi" target="_blank" rel="noopener noreferrer">rumor.fi</a> - connect a wallet and run the demo strategy with a small amount.</p>
  <strong>Next:</strong> multi-strategy support and cross-chain expansion starting with low-cost L2s.</p>

<br>

<h3>- contributing / feedback</h3>
<p>
  Issues and PRs are welcome. If you’re integrating a protocol adapter or proposing a strategy template, please open an issue with
  the target chain, contracts and risk notes.
</p>
<br>

> This repository contains a **demo strategy implementation** used on [rumor.fi](https://rumor.fi/).  
> Connect your wallet on the site to try the **50/50 split** demo <em>(USDT → 50% lend as USDT on Aave, 50% swap to USDC → lend on Aave)</em>. The demo showcases the execution flow and UX we’re building toward.
<br>
<br>

<h3>- security &amp; disclaimer</h3>
<p>
  This is <strong>experimental, non-custodial</strong> software. No warranties. <strong>Not financial advice.</strong>
  Use amounts you can afford to lose. DeFi carries risks <em>(smart contracts, oracles, liquidity, bridges, market condi
>>>>>>> 7151c617d10fa5b787225bb1692e937ad1cc4b99
