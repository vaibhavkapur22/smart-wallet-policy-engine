---
title: Security
layout: default
nav_order: 9
---

# Security Model
{: .no_toc }

Trust assumptions, threat scenarios, and defense-in-depth layers.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Trust Model

The system operates on a **dual-signature** model: every transaction requires both the owner's signature and the backend's attestation. Neither party can move funds unilaterally. This creates a separation of concerns where the owner authorizes intent and the backend validates safety.

| Component | Trust Level | What It Controls |
|:----------|:------------|:-----------------|
| **Smart Contract** | Fully trusted | On-chain enforcement; immutable logic verified by 30+ tests |
| **Owner** | Trusted for authorization | Signs operations, manages guardians, controls pause and lists |
| **Backend Signer** | Trusted for risk assessment | Signs attestations based on simulation and scoring |
| **Guardians** | Semi-trusted | Co-sign medium-risk operations, cancel queued operations |
| **Frontend** | Untrusted | User interface only; no security-critical logic |

## On-Chain Defenses

### Signature Verification

Every execution path verifies EIP-712 typed structured data signatures:

| Function | Signatures Required |
|:---------|:-------------------|
| `execute()` | Owner + Backend attestation |
| `executeWithGuardian()` | Owner + Guardian + Backend attestation |
| `executeQueued()` | None (already authorized at queue time) |

### Replay Protection

| Mechanism | Protection |
|:----------|:-----------|
| **Nonce** | Strictly incrementing counter; each operation consumes exactly one nonce |
| **Expiry** | Attestations have a TTL (default: 1 hour); stale attestations are rejected |
| **EIP-712 Domain** | Chain ID + contract address in domain separator prevent cross-chain and cross-contract replay |

### Reentrancy Protection

All execution functions (`execute`, `executeWithGuardian`, `executeQueued`) use OpenZeppelin's `nonReentrant` modifier. A malicious target contract cannot re-enter the wallet during a `call`.

### Emergency Controls

| Control | Who Can Trigger | Effect |
|:--------|:----------------|:-------|
| **Pause** | Owner | Freezes all `execute*` functions immediately |
| **Cancel Queued** | Owner or any Guardian | Cancels a pending delayed operation |
| **Blocklist** | Owner (on-chain) | Prevents execution to specific addresses regardless of backend decision |
| **Remove Guardian** | Owner | Revokes a compromised guardian's co-sign and cancel ability |

## Off-Chain Defenses

### Risk Engine Coverage

Six independent rules provide overlapping coverage so that a single rule bypass does not compromise the system:

| Rule | What It Catches |
|:-----|:----------------|
| Value-based | High-value transfers (> $100, > $1,000) |
| New recipient | First-time interactions with unknown addresses |
| Unlimited approval | ERC20 approvals that grant unlimited token access |
| Contract reputation | Interactions with blocklisted or unknown contracts |
| Simulation | Transactions that would drain > 50% of wallet balance |
| Large token transfer | Token movements exceeding $5,000 |

### Hard Deny Rules

Three conditions always result in DENY regardless of numeric score:

1. Target is a blocklisted contract
2. Simulation detects asset drain (> 50% balance loss)
3. Unlimited approval to an unknown (non-allowlisted) contract

### Audit Trail

Every policy decision is logged to the database with full context:

| Field | Purpose |
|:------|:--------|
| Timestamp | When the decision was made |
| Wallet address | Which wallet requested the evaluation |
| Target address | Where the transaction would go |
| Value | Wei amount |
| TX type | ETH_TRANSFER, ERC20_TRANSFER, ERC20_APPROVE, CONTRACT_CALL |
| Risk score | Numeric score (0.0 - 1.0) |
| Decision | ALLOW, REQUIRE_SECOND_SIGNATURE, REQUIRE_DELAY, DENY |
| Reason codes | Which rules fired |

## Threat Scenarios

### Compromised Backend Signer Key

**Impact:** Attacker can sign ALLOW attestations for arbitrary transactions.

**Mitigations:**
- Owner signature is still required (attacker needs both keys)
- On-chain blocklist prevents execution to known-bad addresses
- Audit log records all attestations for detection

**Response:**
1. Owner calls `pause()` to freeze the wallet
2. Review audit logs for unauthorized attestations
3. Deploy new backend with fresh signer key
4. Owner calls `setTrustedSigner(newAddress)` to rotate the signer
5. Owner calls `unpause()` to resume operations

### Compromised Owner Key

**Impact:** Attacker can sign operations, modify guardians, change signer, pause/unpause, and transfer ownership.

**Mitigations:**
- Backend still needs to attest -- backend can refuse suspicious requests
- REQUIRE_DELAY operations have a cancellation window for guardians
- Guardians can cancel queued operations before execution

**Response:**
1. Guardian cancels all pending queued operations
2. If the backend detects anomalous behavior, it can refuse to sign attestations
3. Transfer ownership to a new secure address (requires current owner key, so this depends on timing)

### Compromised Guardian Key

**Impact:** Attacker can co-sign medium-risk transactions and cancel pending operations.

**Mitigations:**
- Guardian cannot act alone; owner signature and backend attestation are still required
- Cancelling queued operations is a protective action, not a destructive one

**Response:**
1. Owner calls `removeGuardian(compromisedAddress)`
2. Owner calls `addGuardian(newGuardianAddress)`

### Backend Downtime

**Impact:** No new attestations can be signed. The wallet cannot process new transactions.

**Mitigations:**
- Already-queued operations can still execute via `executeQueued()` after their delay
- Owner can cancel queued operations
- The contract and its funds remain safe; only new operations are blocked

**Response:**
1. Restore backend service
2. No on-chain recovery needed

## Audit Status

{: .warning }
> This contract has not been formally audited. It is designed for testnet and educational use. A professional security audit is recommended before any mainnet deployment with real funds.

## Best Practices

### For Operators

- **Store the backend signer key in an HSM or secrets manager** -- Environment variables are readable by anyone with server access
- **Keep guardian keys on separate devices** -- If the owner and guardian keys are on the same machine, a single compromise defeats the co-signing model
- **Monitor audit logs daily** -- Look for unexpected DENY spikes, unusual ALLOW patterns, or risk scores that don't match expectations
- **Rotate the trusted signer periodically** -- Use `setTrustedSigner()` to rotate without redeploying the contract
- **Maintain the blocklist** -- Add known malicious contracts proactively

### For Developers

- **Never expose private keys in client-side code** -- The frontend should never handle signing keys
- **Restrict CORS in production** -- The default `*` origin is for development only
- **Use HTTPS for all API communication** -- Attestation signatures are sensitive
- **Implement rate limiting** -- Prevent abuse of the `/decide` and `/attest` endpoints
- **Integrate a production simulator** -- The current calldata decoder is MVP-level; services like Tenderly provide deeper transaction simulation
