---
title: Home
layout: home
nav_order: 1
---

# Smart Contract Wallet + Policy Engine
{: .fs-9 }

A smart contract wallet with a risk-based policy engine that simulates transactions, scores risk across six dimensions, and enforces tiered authorization on-chain via EIP-712 signed attestations.
{: .fs-6 .fw-300 }

[Get Started](/smart-wallet-policy-engine/getting-started){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[API Reference](/smart-wallet-policy-engine/api-reference){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Overview

The Smart Contract Wallet + Policy Engine is a three-tier authorization system that sits between a user and their on-chain assets. Every outbound transaction is simulated off-chain, assigned a risk score between 0.0 and 1.0, and routed through one of four enforcement paths before execution. The smart contract verifies cryptographic attestations from the backend before releasing funds, ensuring that no transaction bypasses the policy layer.

### Key Features

- **Four-tier authorization** -- Transactions are classified as ALLOW (immediate), REQUIRE_SECOND_SIGNATURE (guardian co-sign), REQUIRE_DELAY (1-hour timelock queue), or DENY (blocked)
- **Six-rule risk scoring** -- Independent rules evaluate value, recipient reputation, approval patterns, contract trust status, simulation outcomes, and token transfer size
- **EIP-712 attestation signing** -- The backend signs typed structured data that the smart contract verifies on-chain, preventing cross-chain and cross-contract replay attacks
- **Guardian co-signing** -- Medium-risk transactions require a registered guardian to co-sign alongside the owner, adding a second human in the loop
- **Timelock queue with cancellation** -- High-risk operations are queued on-chain for a configurable delay period, during which the owner or any guardian can cancel
- **On-chain allowlist and blocklist** -- Target addresses can be allowlisted (bypass unknown-contract penalty) or blocklisted (always denied) directly in the smart contract
- **Complete audit trail** -- Every policy decision is logged with timestamp, risk score, decision, and reason codes for compliance and forensic analysis
- **Emergency pause** -- The owner can instantly freeze all wallet operations via OpenZeppelin's Pausable mechanism

### Architecture at a Glance

```
User Browser (Next.js)
        |
   POST /decide (tx details)
        |
   [ FastAPI Backend ]
        |
   +----+----+----+
   |         |         |
Simulate   Score    Decide
   |         |         |
   +----+----+----+
        |
   EIP-712 Attestation
        |
   [ PolicySmartWallet.sol ]
        |
   +----+----+----+----+
   |         |         |         |
 ALLOW   GUARDIAN   DELAY    DENY
 (exec)  (co-sign)  (queue)  (revert)
```

### Tech Stack

| Component | Technology |
|:----------|:-----------|
| Smart Contract | Solidity 0.8.24, Foundry, OpenZeppelin (EIP712, Pausable, ReentrancyGuard) |
| Backend | Python 3.10+, FastAPI, Web3.py, SQLAlchemy, eth-account |
| Frontend | Next.js 14, React 18, TypeScript 5, Viem 2, Wagmi 2, TailwindCSS 3 |
| Testing | Forge (30+ Solidity tests), pytest (backend unit tests) |
| CI | GitHub Actions (forge fmt, build, test) |

### Project Structure

```
src/
  PolicySmartWallet.sol        # Main wallet contract (396 lines)
test/
  PolicySmartWallet.t.sol      # Forge test suite (532 lines, 30+ cases)
script/
  Deploy.s.sol                 # Foundry deployment script
backend/
  app/
    main.py                    # FastAPI server (6 core + 9 admin endpoints)
    risk_engine.py             # Risk scoring (6 independent rules)
    policy_engine.py           # Decision mapping (score + reasons -> decision)
    attestations.py            # EIP-712 typed data signing
    simulator.py               # Transaction calldata decoder
    models.py                  # Pydantic request/response schemas
    db.py                      # SQLAlchemy audit log + policy config
    config.py                  # Environment-based configuration
  tests/
    test_policy_engine.py      # pytest unit tests
frontend/
  app/
    page.tsx                   # Dashboard with audit log viewer
    send/page.tsx              # Transaction submission + risk preview
    queue/page.tsx             # Pending delayed operations
    admin/page.tsx             # Policy admin panel (lists management)
  lib/
    api.ts                     # Typed API client for all endpoints
    abi.ts                     # Smart contract ABI definitions
```
