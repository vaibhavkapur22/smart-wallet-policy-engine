# Smart Contract Wallet + Policy Engine — Development Plan

## 1. Project Summary

Build a **smart contract wallet on Ethereum** that applies **risk-based authorization** to wallet actions, similar to how **3DS and fraud systems** add step-up authentication in card payments.

Instead of every wallet action being a simple “valid signature = execute,” the wallet should support:

- **Low-risk transactions** → auto-approve
- **Medium-risk transactions** → require a **second signature**
- **High-risk transactions** → require a **time delay**
- **Very risky / malicious transactions** → **deny execution**

The project combines:

- **Smart contract wallet enforcement**
- **Off-chain risk/policy engine**
- **Transaction simulation before execution**
- **Step-up authorization mechanisms**

This is essentially the crypto equivalent of:

> fraud engine + risk-based authentication + 3DS challenge orchestration

---

## 2. Core Product Idea

### Payments analogy

In card payments:

- low-risk transaction → frictionless approval
- medium/high-risk transaction → challenge / step-up auth
- suspicious transaction → decline

In this crypto wallet:

- low-risk transfer → execute immediately
- moderate-risk transfer → require guardian / second signer
- high-risk action → enforce time delay
- suspicious contract interaction → block

This gives you a very strong bridge from:

- **PayPal fraud systems**
- **3DS / risk orchestration**
- **authentication and liability-like protection models**

into:

- **account abstraction**
- **smart contract wallets**
- **wallet security infrastructure**

---

## 3. High-Level System Architecture

The system should have four major components:

### A. Smart Contract Wallet
On-chain wallet contract that holds assets and enforces policy outcomes.

### B. Policy Engine
Off-chain service that decides what level of authorization is required.

### C. Risk Engine
Off-chain scoring engine that evaluates transaction risk.

### D. Simulation Layer
Previews the impact of a transaction before execution.

### End-to-end flow

1. User initiates a transaction
2. Backend simulates the transaction
3. Backend computes risk score
4. Policy engine determines required auth level
5. Backend signs an attestation of the decision
6. Wallet contract verifies the attestation and enforces the required path
7. Transaction is executed, queued, challenged, or denied

---

## 4. Recommended Tech Stack

### Blockchain / Smart Contracts
- **Ethereum Sepolia** for MVP
- Later: **Ethereum mainnet**, **Base**, or **Arbitrum**
- **Solidity**
- **Foundry** for development and testing
- **OpenZeppelin contracts** for security primitives

### Backend
- **Python**
- **FastAPI**
- **Postgres** for policy configs, logs, audit trail
- **Redis** optional for caching or rate-limiting

### Frontend
- **Next.js**
- **React**
- **TypeScript**
- **wagmi + viem** for wallet interactions

### Simulation / Infrastructure
- **Tenderly** or equivalent transaction simulation tooling
- Optional account abstraction infrastructure:
  - bundler service
  - paymaster service

---

## 5. Development Strategy

Do **not** start with full ERC-4337 complexity.

### Best build order

1. Build a **basic smart contract wallet** with policy enforcement
2. Add **guardian / second signature logic**
3. Add **delayed operation queue**
4. Build **FastAPI risk + policy backend**
5. Add **signed attestations**
6. Add **transaction simulation**
7. Later evolve into **ERC-4337 smart account / account abstraction**

This gives you a simpler path to a working MVP while preserving the long-term architecture.

---

## 6. Functional Requirements

### Wallet must support
- ETH transfers
- ERC20 transfers
- ERC20 approvals
- Generic contract calls
- Nonce / replay protection
- Signature verification
- Guardian / second-signer authorization
- Delayed execution queue
- Cancel queued operations
- Pausable emergency stop

### Policy engine must support
- Value-based rules
- Known recipient vs new recipient logic
- Dangerous contract / approval detection
- Allowlist / blocklist rules
- Simulation-informed decisions
- Decision attestation signing

### Risk engine should support
- Rule-based scoring for MVP
- Reason codes
- Risk score generation
- Extensible interface for future ML scoring

### Frontend should show
- transaction preview
- simulation output
- risk score
- policy decision
- pending queued operations
- guardian approval state
- cancel action for delayed operations

---

## 7. MVP Policy Outcomes

For the first version, use exactly four outcomes:

- `ALLOW`
- `REQUIRE_SECOND_SIGNATURE`
- `REQUIRE_DELAY`
- `DENY`

These map cleanly to wallet enforcement and keep the system easy to reason about.

---

## 8. Smart Contract Design

## 8.1 Main Contract Responsibilities

Create a main wallet contract, for example:

`PolicySmartWallet.sol`

Responsibilities:

- hold funds / tokens
- execute transactions
- verify owner signature
- verify guardian signature when required
- verify backend attestation
- queue high-risk transactions
- allow cancellation of delayed ops
- enforce nonces and expiries

## 8.2 Supporting Modules

You can build these as separate contracts or logical modules.

### A. GuardianManager
Tracks second signers.

Responsibilities:
- add/remove guardian
- guardian existence checks
- optional future threshold support

### B. OperationQueue
Stores high-risk delayed transactions.

Responsibilities:
- hash operations
- store delay expiry time
- allow execution after delay
- allow cancellation during delay window

### C. PolicyConfig
Stores configurable policy settings.

Responsibilities:
- thresholds
- allowlists
- blocklists
- delay durations
- trusted risk signer address

For MVP, these can all be embedded into one contract if you want faster iteration.

---

## 9. On-Chain Enforcement Model

The contract should only enforce outcomes. It should **not** perform heavy risk reasoning on-chain.

### Low-risk path
- owner signs
- backend attests `ALLOW`
- contract executes immediately

### Medium-risk path
- owner signs
- guardian signs
- contract verifies both signatures
- execute

### High-risk path
- owner signs
- backend attests `REQUIRE_DELAY`
- contract stores operation in queue
- after delay expires, operation can be executed
- guardian or owner can cancel during waiting period

### Denied path
- backend attests `DENY`
- contract rejects / reverts

---

## 10. Operation Hashing Design

Every transaction must be represented by a deterministic operation hash.

Suggested fields:

- wallet address
- chain id
- nonce
- target address
- ETH value
- calldata hash
- decision type
- expiry timestamp

Example conceptual hash:

```solidity
bytes32 opHash = keccak256(
    abi.encode(
        address(this),
        block.chainid,
        nonce,
        target,
        value,
        keccak256(data),
        decision,
        expiry
    )
);
```

This hash should be the canonical payload signed by:

- the owner
- the guardian (when needed)
- the backend risk/policy signer

This prevents tampering and replay across different operations.

---

## 11. Attestation Model

The backend should produce a signed policy decision that the smart contract can verify on-chain.

### Attestation fields
- wallet address
- nonce
- target
- value
- calldata hash
- decision
- expiry
- policy version
- optional reason hash

### Recommended approach
Use **EIP-712 structured signing**.

The wallet verifies:
- signature comes from trusted backend signer
- attestation is not expired
- attestation matches the exact operation hash
- policy version is acceptable

This allows the heavy risk logic to remain off-chain while still giving cryptographic enforcement on-chain.

---

## 12. Backend Design

Build two services or one service with clear internal modules.

## 12.1 Risk Scoring API

Use **FastAPI**.

Suggested endpoints:

### `POST /simulate`
Takes tx payload and returns simulation output.

### `POST /score`
Produces a risk score and reason codes.

### `POST /decide`
Applies policy rules and returns one of the four outcomes.

### `POST /attest`
Signs the final decision for the exact transaction payload.

### Example request

```json
{
  "wallet": "0xabc...",
  "chain_id": 11155111,
  "target": "0xdef...",
  "value": "0",
  "data": "0xa9059cbb..."
}
```

### Example response

```json
{
  "risk_score": 0.82,
  "decision": "REQUIRE_SECOND_SIGNATURE",
  "reason_codes": ["NEW_CONTRACT", "HIGH_TOKEN_VALUE"]
}
```

## 12.2 Policy Admin API

Use this to:

- configure thresholds
- manage allowlists / blocklists
- manage trusted signer settings
- inspect queued operations
- view audit trail
- review policy decisions and reason codes

---

## 13. MVP Rule Engine

Do not start with ML. Build a rules engine first.

### Rule 1: Value-based threshold

```python
if usd_value <= 100:
    decision = "ALLOW"
elif usd_value <= 1000:
    decision = "REQUIRE_SECOND_SIGNATURE"
else:
    decision = "REQUIRE_DELAY"
```

### Rule 2: New recipient risk boost

```python
if recipient not in known_recipients:
    risk += 0.25
```

### Rule 3: Dangerous infinite approval

```python
if tx_type == "ERC20_APPROVE" and allowance == "MAX_UINT":
    risk += 0.4
```

### Rule 4: Contract reputation

```python
if target_contract in blocked_contracts:
    decision = "DENY"
elif target_contract not in allowlisted_contracts:
    risk += 0.3
```

### Rule 5: Simulation red flags

```python
if simulation.assets_drained_pct > 0.5:
    decision = "DENY"
if simulation.unexpected_token_approval:
    risk += 0.3
```

### Rule 6: Behavioral anomaly

```python
if tx_hour not in user_normal_hours:
    risk += 0.1
```

The system can later evolve from rules → heuristics → ML-assisted risk scoring.

---

## 14. Simulation Layer

Simulation is one of the strongest parts of this project.

Before execution, you should simulate the transaction to determine:

- whether it reverts
- token balance deltas
- ETH balance deltas
- approvals being set
- whether approval is unlimited
- whether multiple downstream calls create suspicious side effects
- whether the transaction drains significant wallet value

### Why simulation matters
A user may think they are:

- staking tokens
- swapping assets
- approving a dApp

But simulation might reveal:

- an unlimited token approval
- transfer of all wallet funds
- interaction with an unknown contract
- unexpected side effects

That is exactly the kind of signal your policy engine should act on.

---

## 15. Recommended Initial Transaction Types

Do not support everything on day one.

Start with these four categories:

1. **ETH transfer**
2. **ERC20 transfer**
3. **ERC20 approve**
4. **Generic contract call** with simulation

This gives you enough surface area to demonstrate real security value.

---

## 16. Example User Stories

### Story 1: Small trusted payment
User sends a small USDC transfer to a known recipient.

Expected behavior:
- simulation runs
- risk is low
- policy returns `ALLOW`
- executes immediately

### Story 2: Large transfer to new recipient
User sends $5,000 USDC to a new address.

Expected behavior:
- risk score increases
- policy returns `REQUIRE_SECOND_SIGNATURE`
- guardian approval required
- executes after second signature

### Story 3: Dangerous token approval
User approves unlimited token allowance to an unknown contract.

Expected behavior:
- simulation flags infinite approval
- contract not allowlisted
- policy returns `DENY`
- execution blocked

### Story 4: Large risky contract interaction
User interacts with a bridge / swap / new DeFi protocol.

Expected behavior:
- simulation shows large value movement
- policy returns `REQUIRE_DELAY`
- operation is queued for 1 hour
- owner or guardian can cancel before execution

---

## 17. Security Requirements

The following should be built into the system.

### Must-have security features
- replay protection via nonce
- signature expiry timestamps
- backend attestation expiry
- trusted backend signer rotation
- pause switch / emergency stop
- guardian cancellation path
- allowlist / blocklist
- function selector restrictions if needed
- deterministic operation hashes

### Smart contract safety guidelines
- keep on-chain logic minimal and auditable
- avoid putting ML or complex risk logic on-chain
- minimize upgradeability unless necessary
- prefer battle-tested OpenZeppelin patterns
- write full Foundry tests for auth, queueing, cancellation, and edge cases

---

## 18. What Should Stay Off-Chain

Do **not** put the following on-chain:

- ML inference
- behavioral history storage
- IP or device fingerprint data
- simulation engine internals
- third-party contract reputation lookups
- complex risk heuristics

Keep those off-chain, then sign the decision result.

On-chain should only:
- verify signatures
- verify attestation contents
- enforce challenge / delay / deny behavior
- execute valid operations

---

## 19. Suggested Repository Structure

```text
smart-wallet-policy-engine/
  contracts/
    PolicySmartWallet.sol
    GuardianManager.sol
    OperationQueue.sol
    interfaces/
    lib/

  script/
    Deploy.s.sol

  test/
    PolicySmartWallet.t.sol
    DelayFlow.t.sol
    GuardianFlow.t.sol
    AttestationFlow.t.sol

  backend/
    app/
      main.py
      risk_engine.py
      policy_engine.py
      simulator.py
      attestations.py
      models.py
      db.py
      config.py
    tests/

  frontend/
    app/
    components/
    lib/
    hooks/

  docs/
    architecture.md
    threat-model.md
    api-spec.md
```

---

## 20. Milestone Plan

## Phase 1 — Smart Wallet MVP

### Goal
Build a working wallet with on-chain policy enforcement primitives.

### Deliverables
- smart wallet contract
- owner-based execution
- ETH transfer support
- ERC20 transfer support
- guardian support
- nonce / replay protection

### Success criteria
- wallet can execute basic operations securely
- tests pass for owner-only flow and replay protection

---

## Phase 2 — Guardian + Delay Enforcement

### Goal
Add step-up authorization and delayed execution.

### Deliverables
- guardian signature flow
- delayed queue
- queue execution after expiry
- queued operation cancellation

### Success criteria
- moderate-risk tx requires guardian
- high-risk tx requires delay
- cancel path works correctly

---

## Phase 3 — Backend Risk / Policy Engine

### Goal
Move decisioning off-chain while keeping enforcement on-chain.

### Deliverables
- FastAPI backend
- rules engine
- decision model
- reason codes
- signed attestations

### Success criteria
- backend returns valid decisions
- contract verifies backend attestation
- end-to-end request → attestation → execution flow works

---

## Phase 4 — Simulation-Aware Security

### Goal
Add transaction preview and simulation-driven decisions.

### Deliverables
- simulation API integration
- transfer / approval decoding
- dangerous infinite-approval detection
- balance-delta risk inputs

### Success criteria
- simulated high-risk tx is correctly challenged or denied
- frontend can display simulation insights before execution

---

## Phase 5 — Frontend + Admin UX

### Goal
Make the system demonstrable and easy to inspect.

### Deliverables
- transaction review page
- risk score and reason code view
- guardian approval UX
- queued operation list
- cancel action
- policy config dashboard

### Success criteria
- full user journey is demoable without reading raw logs

---

## Phase 6 — ERC-4337 / Account Abstraction Integration

### Goal
Evolve the design into a modern smart account architecture.

### Deliverables
- ERC-4337-compatible validation model
- UserOperation validation logic
- bundler integration
- optional paymaster support

### Success criteria
- wallet logic works in account abstraction flow
- policy-based auth remains intact under ERC-4337 execution model

---

## 21. Testing Strategy

## Smart contract tests
Write Foundry tests for:

- owner execution
- guardian-required execution
- delay-required execution
- cancellation flow
- invalid signature rejection
- expired attestation rejection
- replay attack prevention
- incorrect nonce rejection
- tampered calldata hash rejection

## Backend tests
Write unit/integration tests for:

- policy rule evaluation
- risk score generation
- reason code generation
- attestation signing
- attestation verification payload consistency
- simulation parsing

## End-to-end tests
Test full flow:

- UI / API request
- simulation
- risk decision
- attestation signing
- wallet verification
- final execution / challenge / delay / deny behavior

---

## 22. Threat Model

You should explicitly document what threats the wallet is trying to reduce.

### Threats mitigated
- unauthorized high-value transactions
- compromised primary signer causing asset loss
- dangerous token approvals
- malicious or unknown contract interactions
- accidental wallet draining
- replay or tampering of signed tx payloads

### Threats not fully mitigated
- backend trust compromise if trusted signer is stolen
- user approving malicious action after warnings
- chain-level MEV / censorship issues
- vulnerabilities in third-party protocols after approval/execution

This section is very valuable in interviews and architecture reviews.

---

## 23. Suggested Initial Config

Use this exact config for your first MVP:

### Transfer thresholds
- `< $100` → `ALLOW`
- `$100–$1000` → `REQUIRE_SECOND_SIGNATURE`
- `> $1000` → `REQUIRE_DELAY`

### Risk conditions
- new recipient → increase risk
- unknown contract → increase risk
- infinite approval → deny or high-risk
- large asset-drain simulation → deny

### Delay window
- 1 hour for high-risk actions

### Signers
- 1 primary owner
- 1 guardian
- 1 trusted backend risk signer

---

## 24. Best Demo Scenarios

Your demo should include these flows.

### Demo A — Frictionless low-risk tx
Small ETH or USDC transfer to known address.

### Demo B — Step-up auth
Large transfer requires guardian signature.

### Demo C — Timelock protection
High-risk action gets queued with cancel window.

### Demo D — Malicious approval defense
Unlimited token approval to suspicious contract is denied.

These four flows are enough to communicate the full product value clearly.

---

## 25. Interview Framing

A concise way to describe the project:

> I built a smart contract wallet that applies risk-based authorization to on-chain actions, similar to how fraud systems and 3DS apply step-up authentication in card payments. Low-risk transactions execute frictionlessly, while higher-risk actions require a guardian signature, a delay window, or are blocked entirely. I also added transaction simulation so decisions are based on predicted wallet impact, not just raw calldata.

That framing is one of the biggest strengths of this project.

---

## 26. What Makes This Project Strong

This project stands out because it combines:

- payments security thinking
- auth / 3DS-style orchestration
- smart contract engineering
- policy engines
- transaction simulation
- account abstraction directionality

It is not just “another wallet.”
It is a **wallet security orchestration system**.

---

## 27. Recommended Next Step

Build the **smallest demoable MVP first**:

- Sepolia smart wallet
- owner + guardian support
- value-based rules
- delayed queue
- FastAPI backend
- signed policy attestations
- simple frontend showing risk decision and queue state

Once that works, add:

- simulation-based risk inputs
- richer policy rules
- ERC-4337 support

---

## 28. Final MVP Spec

For version 1, build exactly this:

### On-chain
- Ethereum Sepolia smart wallet
- owner + guardian signatures
- ETH + ERC20 transfer support
- ERC20 approve support
- delay queue
- cancel queued op
- EIP-712 attestation verification

### Off-chain
- FastAPI backend
- rules-based risk engine
- policy decision service
- signed attestations
- audit logs

### Rules
- `< $100` allow
- `$100–$1000` guardian required
- `> $1000` 1-hour delay
- unknown contract + infinite approval = deny

### Frontend
- tx preview
- risk score
- reason codes
- decision state
- pending delayed operations
- cancel action

This scope is ambitious enough to be impressive but still realistic to ship.
