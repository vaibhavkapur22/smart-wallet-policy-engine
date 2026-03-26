---
title: Frontend
layout: default
nav_order: 7
---

# Frontend Guide
{: .no_toc }

The Next.js 14 web interface for transaction submission, queue management, and policy administration.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The frontend is a Next.js 14 application using the App Router. It provides four pages: a dashboard showing audit logs, a transaction submission form with risk preview, a queue viewer for delayed operations, and an admin panel for managing address lists. The frontend communicates with the FastAPI backend and reads on-chain state via Viem.

### Tech Stack

| Library | Version | Purpose |
|:--------|:--------|:--------|
| Next.js | 14 | React framework with App Router |
| React | 18 | UI library |
| TypeScript | 5 | Type safety |
| Viem | 2 | Ethereum client (contract reads, ABI encoding) |
| Wagmi | 2 | React hooks for wallet connection and contract interaction |
| TanStack Query | 5 | Data fetching, caching, and synchronization |
| TailwindCSS | 3 | Utility-first styling (dark theme) |

## Setup

```bash
cd frontend
npm install
npm run dev
```

The UI starts on `http://localhost:3000`.

### Environment Variables

| Variable | Default | Description |
|:---------|:--------|:------------|
| `NEXT_PUBLIC_API_URL` | `http://localhost:8000` | Backend API base URL |
| `NEXT_PUBLIC_WALLET_ADDRESS` | -- | Deployed PolicySmartWallet contract address |
| `NEXT_PUBLIC_CHAIN_ID` | `11155111` | Target chain ID (Sepolia) |

## Pages

### Dashboard (`/`)

The main page displays a summary of all policy decisions made by the system.

**Features:**
- **Summary stats** -- Four cards showing total decisions, allowed count, challenged count (GUARDIAN + DELAY), and denied count
- **Audit log table** -- Scrollable table with columns for timestamp, transaction type, target address, value, risk score, decision, and reason codes
- **Risk visualization** -- Color-coded bars showing the distribution of decisions
- **Real-time refresh** -- Data fetched from `GET /audit-logs` on page load

### Send Transaction (`/send`)

The transaction submission form where users evaluate transactions against the policy engine before executing on-chain.

**Form inputs:**
- Wallet address (the PolicySmartWallet instance)
- Target address (recipient)
- Value in ETH
- Calldata (hex-encoded, optional)

**After submission**, the page calls `POST /decide` and displays a color-coded result card:

| Color | Decision | Meaning |
|:------|:---------|:--------|
| Green | `ALLOW` | Safe to execute immediately |
| Yellow | `REQUIRE_SECOND_SIGNATURE` | Guardian must co-sign before execution |
| Orange | `REQUIRE_DELAY` | Will be queued for 1-hour timelock |
| Red | `DENY` | Transaction blocked |

The result card also shows the transaction type, estimated USD value, risk score, fired reason codes, and simulation details (ETH balance change, token transfers, unlimited approval warnings).

### Pending Queue (`/queue`)

Displays operations that are queued on-chain with a timelock and waiting for the delay period to elapse.

**Information displayed per operation:**
- Operation hash
- Target address and value
- Queue timestamp and `executeAfter` timestamp
- Status label: **Pending** (delay not elapsed), **Ready** (can execute), **Executed**, or **Cancelled**
- Countdown timer showing remaining time

**Actions:**
- **Execute** -- Enabled when `block.timestamp >= executeAfter`. Calls `executeQueued()` on the contract.
- **Cancel** -- Available to owner and guardians. Calls `cancelQueued(opHash)` on the contract.

### Admin Panel (`/admin`)

Policy configuration and address list management.

**Policy threshold display** -- Four cards showing the current decision thresholds:

| Decision | Condition |
|:---------|:----------|
| ALLOW | Value < $100 and score < 0.4 |
| REQUIRE_SECOND_SIGNATURE | Value $100-$1,000 or score 0.4-0.7 |
| REQUIRE_DELAY | Value > $1,000 or score >= 0.7 |
| DENY | Blocklisted, drained, or unlimited+unknown |

**Address list managers** -- Three sections with add/remove functionality:

1. **Known Recipients** -- Trusted addresses that bypass the `NEW_RECIPIENT` penalty. Syncs with `POST/DELETE /admin/known-recipients`.
2. **Allowlisted Contracts** -- Verified contracts that bypass the `UNKNOWN_CONTRACT` penalty. Syncs with `POST/DELETE /admin/allowlist`.
3. **Blocked Contracts** -- Contracts that are always denied. Syncs with `POST/DELETE /admin/blocklist`.

Each list loads on page mount and updates optimistically on add/remove.

## API Client

The TypeScript API client (`lib/api.ts`) provides typed functions for all backend endpoints:

```
simulate(tx)          --> SimulationResult
decide(tx)            --> PolicyDecision
attest(params)        --> AttestationResponse
getAuditLogs(limit?)  --> AuditLogEntry[]

addKnownRecipient(address)    --> void
getKnownRecipients()          --> string[]
removeKnownRecipient(address) --> void

addToAllowlist(address)       --> void
getAllowlist()                 --> string[]
removeFromAllowlist(address)  --> void

addToBlocklist(address)       --> void
getBlocklist()                --> string[]
removeFromBlocklist(address)  --> void
```

## Contract ABI

The contract ABI (`lib/abi.ts`) includes all functions needed for on-chain interaction:

**Write functions:** `execute`, `executeWithGuardian`, `executeQueued`, `cancelQueued`

**Read functions:** `owner`, `nonce`, `trustedSigner`, `delayDuration`, `isGuardian`, `getGuardians`, `getQueuedOpHashes`, `getQueuedOperation`, `hashOperation`, `paused`

**Events:** `Executed`, `OperationQueued`, `OperationCancelled`, `OperationExecutedFromQueue`
