---
title: Smart Contract
layout: default
nav_order: 4
---

# Smart Contract Reference
{: .no_toc }

Complete reference for the PolicySmartWallet Solidity contract.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

`PolicySmartWallet` is a Solidity 0.8.24 contract that holds ETH and ERC20 tokens and enforces risk-based authorization via EIP-712 signed attestations. It inherits from three OpenZeppelin contracts:

| Inheritance | Purpose |
|:------------|:--------|
| **EIP712** | Typed structured data signing and domain separator |
| **Pausable** | Emergency freeze mechanism |
| **ReentrancyGuard** | Reentrancy protection on all execution functions |

The contract is 396 lines of Solidity with 30+ test cases in the Forge test suite.

## Types

### Decision Enum

```solidity
enum Decision {
    ALLOW,                    // 0 -- execute immediately
    REQUIRE_SECOND_SIGNATURE, // 1 -- guardian must co-sign
    REQUIRE_DELAY,            // 2 -- queue with timelock
    DENY                      // 3 -- revert
}
```

### Operation Struct

```solidity
struct Operation {
    address target;      // Transaction recipient
    uint256 value;       // ETH value in wei
    bytes   data;        // Calldata (hashed to bytes32 for EIP-712)
    uint256 nonce;       // Must match contract's current nonce
    Decision decision;   // Policy decision from backend
    uint256 expiry;      // Attestation expiration (unix timestamp)
}
```

### QueuedOp Struct

```solidity
struct QueuedOp {
    bytes32 opHash;        // EIP-712 hash of the operation
    uint256 executeAfter;  // block.timestamp + delayDuration
    bool    executed;      // Prevents double-execution
    bool    cancelled;     // Set by cancelQueued()
}
```

## State Variables

| Variable | Type | Default | Description |
|:---------|:-----|:--------|:------------|
| `owner` | `address` | Constructor arg | Wallet owner; can execute, manage guardians, pause |
| `trustedSigner` | `address` | Constructor arg | Backend signer; verified on every attestation |
| `nonce` | `uint256` | `0` | Increments on every successful execution |
| `delayDuration` | `uint256` | Constructor arg | Timelock period for REQUIRE_DELAY (seconds) |
| `guardians` | `address[]` | 1 initial | Registered guardian addresses |
| `isGuardian` | `mapping(address => bool)` | -- | O(1) guardian lookup |
| `queue` | `mapping(bytes32 => QueuedOp)` | -- | Pending delayed operations |
| `queuedOpHashes` | `bytes32[]` | -- | All queued operation hashes (for enumeration) |
| `allowlistedTargets` | `mapping(address => bool)` | -- | Trusted target addresses |
| `blocklistedTargets` | `mapping(address => bool)` | -- | Blocked target addresses |

## Core Functions

### execute

```solidity
function execute(
    Operation calldata op,
    bytes calldata ownerSig,
    bytes calldata attestationSig
) external whenNotPaused nonReentrant
```

Primary execution function for the **ALLOW** and **REQUIRE_DELAY** paths.

**Validation steps:**
1. Check `op.nonce == nonce` (replay protection)
2. Check `block.timestamp <= op.expiry` (attestation freshness)
3. Recover and verify owner signature against `owner`
4. Recover and verify attestation signature against `trustedSigner`

**Behavior by decision:**

| Decision | Behavior |
|:---------|:---------|
| `ALLOW` | Execute `target.call{value}(data)` immediately, increment nonce, emit `Executed` |
| `REQUIRE_DELAY` | Store `QueuedOp` with `executeAfter = block.timestamp + delayDuration`, increment nonce, emit `OperationQueued` |
| `DENY` | Revert with `"Denied by policy"` |
| `REQUIRE_SECOND_SIGNATURE` | Revert with `"Use executeWithGuardian"` |

### executeWithGuardian

```solidity
function executeWithGuardian(
    Operation calldata op,
    bytes calldata ownerSig,
    bytes calldata guardianSig,
    bytes calldata attestationSig
) external whenNotPaused nonReentrant
```

Execution function for the **REQUIRE_SECOND_SIGNATURE** path. Requires three valid signatures.

**Additional validation:**
- Recovers the guardian signer and checks `isGuardian[recoveredGuardian]`
- Reverts if the decision is not `REQUIRE_SECOND_SIGNATURE`

### executeQueued

```solidity
function executeQueued(
    Operation calldata op
) external whenNotPaused nonReentrant
```

Executes a previously queued operation after the delay period has elapsed. No signatures required -- the operation was already authorized at queue time.

**Validation:**
- Recomputes `opHash` from the operation and checks it exists in `queue`
- Checks `block.timestamp >= queuedOp.executeAfter`
- Checks `!queuedOp.executed && !queuedOp.cancelled`
- Marks `executed = true` and calls `target.call{value}(data)`

### cancelQueued

```solidity
function cancelQueued(bytes32 opHash) external
```

Cancels a pending queued operation. Callable by the owner or any registered guardian. Sets `cancelled = true` on the `QueuedOp` and emits `OperationCancelled`.

## Admin Functions

All admin functions are restricted to the owner via an `onlyOwner` modifier.

### Guardian Management

```solidity
function addGuardian(address guardian) external     // Adds to guardians[] and isGuardian mapping
function removeGuardian(address guardian) external   // Removes from both
function getGuardians() external view returns (address[] memory)
```

### Configuration

```solidity
function setTrustedSigner(address _trustedSigner) external  // Rotate backend signer
function setDelayDuration(uint256 _delayDuration) external   // Adjust timelock period
```

### Allowlist and Blocklist

```solidity
function setAllowlistedTarget(address target, bool status) external
function setBlocklistedTarget(address target, bool status) external
```

Allowlisted targets avoid the `UNKNOWN_CONTRACT` risk penalty. Blocklisted targets are always denied by the policy engine and serve as an on-chain safety net.

### Emergency Controls

```solidity
function pause() external    // Blocks all execute* functions
function unpause() external  // Resumes normal operation
```

### Ownership

```solidity
function transferOwnership(address newOwner) external
```

## Events

| Event | Emitted When |
|:------|:-------------|
| `Executed(address target, uint256 value, bytes data, Decision decision)` | Transaction executes immediately (ALLOW or GUARDIAN path) |
| `OperationQueued(bytes32 opHash, uint256 executeAfter)` | Transaction queued (REQUIRE_DELAY path) |
| `OperationCancelled(bytes32 opHash)` | Queued operation cancelled |
| `OperationExecutedFromQueue(bytes32 opHash)` | Queued operation executed after delay |

## EIP-712 Details

### Type Hash

```solidity
bytes32 public constant OPERATION_TYPEHASH = keccak256(
    "Operation(address target,uint256 value,bytes32 dataHash,uint256 nonce,uint8 decision,uint256 expiry)"
);
```

### Hash Computation

```solidity
function hashOperation(Operation calldata op) public view returns (bytes32)
```

Computes the EIP-712 typed data hash for an operation. Used internally for signature verification and externally for computing queue keys. The `data` field is hashed to `keccak256(op.data)` before inclusion in the struct hash.

## Deployment

The deployment script (`script/Deploy.s.sol`) reads from environment variables:

| Variable | Required | Description |
|:---------|:---------|:------------|
| `DEPLOYER_PRIVATE_KEY` | Yes | Deployer account (needs ETH for gas) |
| `WALLET_OWNER` | Yes | Wallet owner address |
| `TRUSTED_SIGNER` | Yes | Backend signer address |
| `GUARDIAN` | Yes | Initial guardian address |
| `DELAY_DURATION` | No | Timelock period in seconds (default: 3600) |

```bash
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify
```
