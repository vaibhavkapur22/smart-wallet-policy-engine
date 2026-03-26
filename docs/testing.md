---
title: Testing
layout: default
nav_order: 10
---

# Testing Guide
{: .no_toc }

How to run the test suites and what they cover.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The project includes two test suites: a Forge test suite for the Solidity smart contract (30+ tests, 532 lines) and a pytest suite for the Python backend (simulator, risk engine, and policy engine). The CI pipeline runs the Solidity tests on every push and pull request via GitHub Actions.

## Smart Contract Tests

### Running

```bash
# All tests with verbose output
forge test -vvv

# Specific test by name
forge test --match-test testExecuteAllowETH -vvv

# Gas report
forge test --gas-report

# Format check (also runs in CI)
forge fmt --check
```

### Test Coverage by Category

#### Constructor (4 tests)

| Test | Validates |
|:-----|:---------|
| `testConstructor` | Owner, signer, guardian, and delay are set correctly |
| `testConstructorZeroOwner` | Reverts on zero-address owner |
| `testConstructorZeroSigner` | Reverts on zero-address signer |
| `testConstructorZeroGuardian` | Reverts on zero-address guardian |

#### ALLOW Path (3 tests)

| Test | Validates |
|:-----|:---------|
| `testExecuteAllowETH` | Plain ETH transfer executes immediately with ALLOW decision |
| `testExecuteAllowERC20Transfer` | ERC20 `transfer()` executes with ALLOW decision |
| `testExecuteAllowERC20Approve` | ERC20 `approve()` executes with ALLOW decision |

#### DENY Path (1 test)

| Test | Validates |
|:-----|:---------|
| `testExecuteDeny` | Transaction with DENY decision reverts with "Denied by policy" |

#### REQUIRE_SECOND_SIGNATURE Path (3 tests)

| Test | Validates |
|:-----|:---------|
| `testExecuteWithGuardian` | Valid owner + guardian + attestation succeeds |
| `testExecuteWithGuardianInvalidGuardian` | Non-registered guardian signer reverts |
| `testExecuteWithGuardianWrongDecision` | Wrong decision type (not REQUIRE_SECOND_SIGNATURE) reverts |

#### REQUIRE_DELAY Path (6 tests)

| Test | Validates |
|:-----|:---------|
| `testExecuteDelayQueues` | REQUIRE_DELAY queues the operation instead of executing |
| `testExecuteQueuedAfterDelay` | Queued operation executes after delay period elapses |
| `testExecuteQueuedTooEarly` | Premature execution (before delay) reverts |
| `testCancelQueued` | Owner can cancel a queued operation |
| `testCancelQueuedByGuardian` | Guardian can cancel a queued operation |
| `testExecuteQueuedAlreadyExecuted` | Double-execution of same queued operation reverts |

#### Signature Validation (3 tests)

| Test | Validates |
|:-----|:---------|
| `testInvalidOwnerSignature` | Wrong owner signature reverts |
| `testInvalidAttestationSignature` | Wrong backend attestation signature reverts |
| `testExpiredAttestation` | Expired attestation (past expiry timestamp) reverts |

#### Replay Protection (2 tests)

| Test | Validates |
|:-----|:---------|
| `testReplayProtection` | Same nonce cannot be used twice (nonce consumed on first use) |
| `testWrongNonce` | Operation with wrong nonce value reverts |

#### Guardian Management (3 tests)

| Test | Validates |
|:-----|:---------|
| `testAddGuardian` | Owner can add a new guardian |
| `testRemoveGuardian` | Owner can remove an existing guardian |
| `testAddGuardianNotOwner` | Non-owner cannot add a guardian |

#### Admin Functions (5 tests)

| Test | Validates |
|:-----|:---------|
| `testSetTrustedSigner` | Owner can update the trusted signer address |
| `testSetDelayDuration` | Owner can change the timelock period |
| `testPause` | Owner can pause; all execute functions revert when paused |
| `testUnpause` | Owner can unpause; operations resume normally |
| `testTransferOwnership` | Owner can transfer ownership to a new address |

#### Other (1 test)

| Test | Validates |
|:-----|:---------|
| `testReceiveETH` | Contract can receive plain ETH transfers (receive function) |

## Backend Tests

### Running

```bash
cd backend
pytest tests/ -v
```

### Test Coverage

#### Simulator Tests

| Test | Validates |
|:-----|:---------|
| `test_simulate_eth_transfer` | Detects native ETH transfers (value > 0, empty calldata) |
| `test_simulate_erc20_transfer` | Decodes `transfer(address,uint256)` from selector `0xa9059cbb` |
| `test_simulate_erc20_approve` | Detects `approve(address,uint256)` from selector `0x095ea7b3` |
| `test_simulate_unlimited_approval` | Flags approvals with amount >= 2^255 as `unlimited_approval: true` |

#### Risk Engine Tests

| Test | Validates |
|:-----|:---------|
| `test_low_value_known_recipient` | Score near 0.0 for small transfers to known addresses |
| `test_high_value_new_recipient` | Score reflects HIGH_VALUE + NEW_RECIPIENT penalties |
| `test_unlimited_approval_risk` | Unlimited approval adds +0.4 to risk score |
| `test_blocked_contract` | Blocklisted contract sets score to 1.0 |
| `test_known_recipient_no_penalty` | Known recipients do not receive NEW_RECIPIENT penalty |

#### Policy Engine Tests

| Test | Validates |
|:-----|:---------|
| `test_allow_decision` | Low score (< 0.4) maps to ALLOW |
| `test_second_sig_decision` | Medium score (0.4-0.7) maps to REQUIRE_SECOND_SIGNATURE |
| `test_delay_decision` | High score (>= 0.7) maps to REQUIRE_DELAY |
| `test_deny_blocked_contract` | BLOCKED_CONTRACT reason maps to DENY |
| `test_deny_unlimited_unknown` | UNLIMITED_APPROVAL + UNKNOWN_CONTRACT maps to DENY |

## CI Pipeline

The GitHub Actions workflow (`.github/workflows/test.yml`) runs on every push and pull request:

```
1. Checkout repository with submodules (forge-std, openzeppelin-contracts)
2. Install Foundry toolchain
3. forge fmt --check       # Enforce code formatting
4. forge build --sizes     # Compile and check contract sizes
5. forge test -vvv         # Run full test suite with verbose output
```

The pipeline uses the `ci` Foundry profile and runs on `ubuntu-latest`.
