---
title: Architecture
layout: default
nav_order: 3
---

# Architecture
{: .no_toc }

A deep dive into the three-tier system design, transaction flows, and security model.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## System Overview

The system follows a three-tier architecture where the frontend is untrusted, the backend makes risk decisions and signs attestations, and the smart contract enforces those decisions on-chain. Both the owner's signature and the backend's attestation are required for every transaction -- neither party can act unilaterally.

```
+───────────────────────+      +───────────────────────+      +───────────────────────+
|                       |      |                       |      |                       |
|    Frontend           |      |    Backend            |      |    Smart Contract     |
|    (Next.js 14)       | ---> |    (FastAPI)          | ---> |    (Solidity 0.8.24)  |
|                       |      |                       |      |                       |
+───────────────────────+      +───────────────────────+      +───────────────────────+
|                       |      |                       |      |                       |
| - TX submission form  |      | - TX simulation       |      | - EIP-712 verify      |
| - Risk preview cards  |      | - 6-rule risk scoring |      | - Nonce enforcement   |
| - Queue viewer        |      | - Policy decision     |      | - Execute / queue     |
| - Audit log table     |      | - EIP-712 signing     |      | - Guardian co-sign    |
| - Admin list mgmt     |      | - Audit logging (SQL) |      | - Pause / blocklist   |
|                       |      |                       |      |                       |
+───────────────────────+      +───────────────────────+      +───────────────────────+
```

| Layer | Trust Level | Responsibility |
|:------|:------------|:---------------|
| **Frontend** | Untrusted | User interface only; all inputs are validated server-side |
| **Backend** | Trusted for risk assessment | Simulates transactions, computes risk scores, signs EIP-712 attestations |
| **Smart Contract** | Fully trusted | On-chain enforcement via signature verification, nonce tracking, and timelocks |

## Transaction Lifecycle

Every transaction moves through a pipeline of simulation, scoring, decision, attestation, and on-chain enforcement. The pipeline produces one of four outcomes:

```
                              POST /decide
                                  |
                           +-----------+
                           | Simulator |  Decode calldata
                           +-----+-----+
                                 |
                           +-----+-----+
                           |Risk Engine|  Apply 6 rules
                           +-----+-----+
                                 |
                           +-----+------+
                           |Policy Engine|  Map to decision
                           +-----+------+
                                 |
              +--------+---------+---------+--------+
              |        |                   |        |
           ALLOW   GUARDIAN             DELAY     DENY
              |        |                   |        |
          Immediate  Co-sign           Queue     Reject
          execution  required          1 hour    (no attestation)
              |        |                   |
          execute()  executeWith       execute()
                     Guardian()          |
                                     executeQueued()
                                     (after delay)
```

### ALLOW Path (Low Risk)

Transactions with a risk score below 0.4 and value under $100 execute immediately. The owner signs the operation, the backend signs an attestation, and the contract executes in a single call.

1. Frontend sends transaction details to `POST /decide`
2. Backend simulates, scores risk at < 0.4, returns `ALLOW`
3. Frontend requests attestation via `POST /attest`
4. Owner signs the EIP-712 operation
5. Frontend calls `execute(op, ownerSig, attestationSig)` on-chain
6. Contract verifies both signatures, increments nonce, executes the call

### REQUIRE_SECOND_SIGNATURE Path (Medium Risk)

Transactions with a risk score between 0.4 and 0.7 or value between $100 and $1,000 require a guardian co-signature. This adds a second human in the loop without introducing delay.

1. Policy engine returns `REQUIRE_SECOND_SIGNATURE`
2. A registered guardian reviews and signs the operation
3. Frontend calls `executeWithGuardian(op, ownerSig, guardianSig, attestationSig)`
4. Contract verifies all three signatures (owner, guardian, backend)
5. Contract confirms the guardian signer is registered via `isGuardian` mapping
6. Transaction executes immediately

### REQUIRE_DELAY Path (High Risk)

Transactions with a risk score at or above 0.7 or value above $1,000 are queued on-chain with a configurable timelock (default: 3600 seconds).

1. Policy engine returns `REQUIRE_DELAY`
2. Frontend calls `execute()` -- contract queues the operation instead of executing
3. Contract stores a `QueuedOp` with `executeAfter = block.timestamp + delayDuration`
4. Emits `OperationQueued(opHash, executeAfter)` event
5. After the delay period, anyone calls `executeQueued(op)`
6. During the delay, the owner or any guardian can call `cancelQueued(opHash)`

### DENY Path (Critical Risk)

Transactions targeting blocklisted contracts, draining assets, or combining unlimited approvals with unknown contracts are denied outright. No attestation is signed.

1. Policy engine identifies a hard deny condition
2. Backend returns `DENY` with reason codes
3. Frontend displays the denial -- no on-chain interaction occurs
4. Decision is logged to the audit database

## Signature Architecture

The system uses EIP-712 typed structured data for all signatures. This prevents signing opaque byte strings and enables cross-chain replay protection.

### EIP-712 Domain

```
EIP712Domain {
    name:              "PolicySmartWallet"
    version:           "1"
    chainId:           <target chain ID>
    verifyingContract:  <wallet contract address>
}
```

### Operation Type

```
Operation {
    address target       // Transaction recipient
    uint256 value        // Wei value
    bytes32 dataHash     // keccak256(calldata)
    uint256 nonce        // Strictly incrementing
    uint8   decision     // 0=ALLOW, 1=GUARDIAN, 2=DELAY, 3=DENY
    uint256 expiry       // Attestation expiration (unix timestamp)
}
```

The `data` field is hashed to `bytes32 dataHash` before signing because EIP-712 does not support dynamic `bytes` types directly.

### Signature Roles

| Signer | What They Sign | Required For |
|:-------|:---------------|:-------------|
| **Owner** | Full Operation struct | Every execution path |
| **Backend (Trusted Signer)** | Full Operation struct (attestation) | Every execution path |
| **Guardian** | Full Operation struct | REQUIRE_SECOND_SIGNATURE only |

### Replay Protection

| Mechanism | What It Prevents |
|:----------|:-----------------|
| **Nonce** | Re-executing the same operation (strictly incrementing counter) |
| **Expiry** | Using stale attestations (default: 1 hour TTL) |
| **Chain ID in domain** | Replaying signatures on a different chain |
| **Contract address in domain** | Replaying signatures against a different wallet instance |

## Security Model

### API Authentication

The backend currently operates without API key authentication. In production, add authentication middleware and restrict CORS to your frontend domain.

### Webhook-Free Design

Unlike payment orchestrators, this system does not use webhooks. The frontend polls the contract state directly (queued operations, execution status) and the backend provides audit logs via `GET /audit-logs`.

### Custodial Model

The backend holds the trusted signer private key and signs attestations on every policy decision. This key should be stored in a hardware security module (HSM) or secrets manager in production. The owner's private key remains with the user and is never sent to the backend.

### Defense in Depth

| Layer | Defense |
|:------|:--------|
| **Off-chain simulation** | Detects asset drains, unlimited approvals, and unknown contracts before signing |
| **Risk scoring** | Six independent rules provide overlapping coverage |
| **Hard deny rules** | Blocklisted contracts and dangerous approval patterns are always rejected |
| **On-chain blocklist** | Safety net even if the backend signer is compromised |
| **Nonce + expiry** | Prevents replay and stale attestation attacks |
| **ReentrancyGuard** | Prevents malicious target contracts from re-entering the wallet |
| **Pausable** | Owner can freeze all operations instantly |
| **Timelock** | High-risk operations have a cancellation window |
