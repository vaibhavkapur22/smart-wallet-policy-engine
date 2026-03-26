---
title: Risk Engine
layout: default
nav_order: 5
---

# Risk Engine
{: .no_toc }

How transactions are simulated, scored across six dimensions, and routed to policy decisions.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The risk engine is the core intelligence of the policy system. For every transaction, it runs a three-stage pipeline: simulate the calldata to understand what the transaction does, apply six independent scoring rules to quantify risk, and map the resulting score and reason codes to one of four enforcement decisions. The entire pipeline executes synchronously in a single `POST /decide` request.

## Pipeline

```
Transaction Request (from, to, value, data)
        |
   [ 1. Simulator ]      Decode calldata, identify TX type, estimate USD value
        |
   [ 2. Risk Engine ]    Apply 6 rules, accumulate score (0.0 - 1.0)
        |
   [ 3. Policy Engine ]  Map score + reason codes to decision
        |
   PolicyDecision { decision, risk_score, reason_codes, simulation }
```

## Stage 1: Transaction Simulator

The simulator decodes raw transaction calldata to determine what a transaction will do before it executes. It identifies the transaction type, extracts parameters, and estimates the USD value.

### Supported Transaction Types

| Type | Detection Method | Details Extracted |
|:-----|:-----------------|:------------------|
| `ETH_TRANSFER` | `value > 0` and empty calldata | Amount in ETH, USD estimate |
| `ERC20_TRANSFER` | Function selector `0xa9059cbb` | Recipient address, token amount |
| `ERC20_APPROVE` | Function selector `0x095ea7b3` | Spender address, allowance amount |
| `CONTRACT_CALL` | Non-empty calldata, unrecognized selector | Raw calldata (flagged as unknown) |

### USD Estimation

ETH transfers are valued at `value_eth * ETH_PRICE_USD` where `ETH_PRICE_USD` is configurable (default: $3,000). ERC20 transfers use the raw token amount as a proxy. A production deployment should integrate a price oracle for accurate token valuation.

### Simulation Output

The simulator produces a `SimulationResult` containing:

| Field | Type | Description |
|:------|:-----|:------------|
| `tx_type` | string | One of the four transaction types above |
| `estimated_value_usd` | float | USD value estimate |
| `eth_balance_change` | float | ETH delta (negative for outgoing) |
| `token_transfers` | list | Token movements with address, amount |
| `unlimited_approval` | bool | True if approval amount >= 2^255 |
| `warnings` | list | Human-readable warning strings |

## Stage 2: Risk Scoring

The risk engine applies six independent rules to the simulation output. Each rule adds a score increment. The increments accumulate and are clamped to `[0.0, 1.0]`.

```
final_score = clamp(rule_1 + rule_2 + rule_3 + rule_4 + rule_5 + rule_6, 0.0, 1.0)
```

### Rule 1: Value-Based Risk

Evaluates the estimated USD value of the transaction against two thresholds.

| Condition | Score Added | Reason Code |
|:----------|:-----------|:------------|
| Value > $1,000 | +0.30 | `HIGH_VALUE` |
| Value > $100 | +0.15 | `MEDIUM_VALUE` |
| Value <= $100 | +0.00 | -- |

### Rule 2: New Recipient

Checks whether the target address exists in the known recipients set. Unknown recipients represent a higher risk because there is no prior transaction history.

| Condition | Score Added | Reason Code |
|:----------|:-----------|:------------|
| Target not in known recipients | +0.25 | `NEW_RECIPIENT` |
| Target is known | +0.00 | -- |

Recipients can be added via `POST /admin/known-recipients` or the admin UI.

### Rule 3: Unlimited Approval

Detects ERC20 `approve()` calls with dangerously high allowances. An unlimited approval grants the spender access to all current and future tokens.

| Condition | Score Added | Reason Code |
|:----------|:-----------|:------------|
| Approval amount >= 2^255 | +0.40 | `UNLIMITED_APPROVAL` |
| Normal approval | +0.00 | -- |

### Rule 4: Contract Reputation

Evaluates the target address against the allowlist and blocklist. Blocklisted targets immediately receive the maximum score.

| Condition | Score Added | Reason Code |
|:----------|:-----------|:------------|
| Target is blocklisted | 1.00 (max) | `BLOCKED_CONTRACT` |
| Target not allowlisted | +0.30 | `UNKNOWN_CONTRACT` |
| Target is allowlisted | +0.00 | -- |

### Rule 5: Simulation Red Flags

Checks if the simulation detected a catastrophic outcome where more than 50% of the wallet's ETH balance would be drained.

| Condition | Score Added | Reason Code |
|:----------|:-----------|:------------|
| ETH balance drained > 50% | 1.00 (max) | `ASSETS_DRAINED` |
| Normal simulation | +0.00 | -- |

### Rule 6: Large Token Transfer

Adds a penalty for high-value token movements, separate from the value-based risk rule.

| Condition | Score Added | Reason Code |
|:----------|:-----------|:------------|
| Token transfer value > $5,000 | +0.15 | `LARGE_TOKEN_TRANSFER` |
| Below threshold | +0.00 | -- |

## Stage 3: Policy Engine

The policy engine maps the risk score and reason codes to a final decision. It evaluates conditions in priority order: hard deny checks first, then value-based thresholds, then score-based thresholds.

### Hard Deny Conditions

These conditions always result in `DENY`, regardless of the numeric score:

| Condition | Reason |
|:----------|:-------|
| `BLOCKED_CONTRACT` in reason codes | Target is on the blocklist |
| `ASSETS_DRAINED` in reason codes | Simulation detected catastrophic loss |
| `UNLIMITED_APPROVAL` + `UNKNOWN_CONTRACT` both present | Unlimited approval to an untrusted contract |

### Value-Based Thresholds

If no hard deny condition applies, the engine checks the transaction's USD value:

| USD Value | Decision |
|:----------|:---------|
| > $1,000 | `REQUIRE_DELAY` |
| > $100 | `REQUIRE_SECOND_SIGNATURE` |

### Score-Based Thresholds

If no value threshold applies, the engine falls back to the numeric risk score:

| Risk Score | Decision |
|:-----------|:---------|
| >= 0.7 | `REQUIRE_DELAY` |
| >= 0.4 | `REQUIRE_SECOND_SIGNATURE` |
| < 0.4 | `ALLOW` |

### Decision Priority

```
1. Hard deny conditions      (highest priority)
2. Value-based thresholds
3. Score-based thresholds    (lowest priority)
```

## Example Scoring

### Low Risk: 0.01 ETH to Known Address

| Rule | Score | Reason |
|:-----|:------|:-------|
| Value ($30) | +0.00 | Below $100 threshold |
| Recipient | +0.00 | Known recipient |
| Approval | +0.00 | Not an approval |
| Reputation | +0.00 | N/A (EOA) |
| Simulation | +0.00 | Normal |
| Token transfer | +0.00 | N/A |
| **Total** | **0.00** | |

**Decision:** `ALLOW`

### Medium Risk: 0.05 ETH (~$150) to Unknown Address

| Rule | Score | Reason |
|:-----|:------|:-------|
| Value ($150) | +0.15 | `MEDIUM_VALUE` |
| Recipient | +0.25 | `NEW_RECIPIENT` |
| Approval | +0.00 | Not an approval |
| Reputation | +0.00 | N/A |
| Simulation | +0.00 | Normal |
| Token transfer | +0.00 | N/A |
| **Total** | **0.40** | |

**Decision:** `REQUIRE_SECOND_SIGNATURE` (score >= 0.4)

### High Risk: 0.5 ETH (~$1,500) to Unknown Address

| Rule | Score | Reason |
|:-----|:------|:-------|
| Value ($1,500) | +0.30 | `HIGH_VALUE` |
| Recipient | +0.25 | `NEW_RECIPIENT` |
| Approval | +0.00 | Not an approval |
| Reputation | +0.00 | N/A |
| Simulation | +0.00 | Normal |
| Token transfer | +0.00 | N/A |
| **Total** | **0.55** | |

**Decision:** `REQUIRE_DELAY` (value > $1,000, overrides score threshold)

### Critical: Unlimited Approval on Unknown Contract

| Rule | Score | Reason |
|:-----|:------|:-------|
| Value ($0) | +0.00 | Approval, not transfer |
| Recipient | +0.25 | `NEW_RECIPIENT` |
| Approval | +0.40 | `UNLIMITED_APPROVAL` |
| Reputation | +0.30 | `UNKNOWN_CONTRACT` |
| Simulation | +0.00 | Normal |
| Token transfer | +0.00 | N/A |
| **Total** | **0.95** | |

**Decision:** `DENY` (hard deny: `UNLIMITED_APPROVAL` + `UNKNOWN_CONTRACT`)
