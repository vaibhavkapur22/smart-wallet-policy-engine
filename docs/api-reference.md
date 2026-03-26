---
title: API Reference
layout: default
nav_order: 6
---

# API Reference
{: .no_toc }

Complete endpoint documentation for the FastAPI backend.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Base URL

The API runs on `http://localhost:8000` by default. All endpoints accept and return JSON.

## Core Endpoints

### POST /decide

The primary endpoint. Runs the full pipeline: simulate, score, decide, and log. This is the endpoint the frontend calls when a user submits a transaction.

```bash
curl -X POST http://localhost:8000/decide \
  -H "Content-Type: application/json" \
  -d '{
    "from_address": "0x1234567890abcdef1234567890abcdef12345678",
    "to_address": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    "value": "1000000000000000000",
    "data": "0x"
  }'
```

**Request Body:**

| Field | Type | Description |
|:------|:-----|:------------|
| `from_address` | string | Sender wallet address |
| `to_address` | string | Target address |
| `value` | string | Wei value (as decimal string) |
| `data` | string | Hex-encoded calldata (`"0x"` for plain ETH transfers) |

**Response:**

```json
{
  "decision": "REQUIRE_SECOND_SIGNATURE",
  "risk_score": 0.4,
  "reason_codes": ["MEDIUM_VALUE", "NEW_RECIPIENT"],
  "simulation": {
    "tx_type": "ETH_TRANSFER",
    "estimated_value_usd": 3000.0,
    "eth_balance_change": -1.0,
    "token_transfers": [],
    "unlimited_approval": false,
    "warnings": []
  }
}
```

The `decision` field is one of: `ALLOW`, `REQUIRE_SECOND_SIGNATURE`, `REQUIRE_DELAY`, `DENY`.

This endpoint also writes an audit log entry to the database.

### POST /simulate

Run only the simulation stage without scoring or deciding.

```bash
curl -X POST http://localhost:8000/simulate \
  -H "Content-Type: application/json" \
  -d '{
    "from_address": "0x...",
    "to_address": "0x...",
    "value": "1000000000000000000",
    "data": "0x"
  }'
```

**Response:**

```json
{
  "tx_type": "ETH_TRANSFER",
  "estimated_value_usd": 3000.0,
  "eth_balance_change": -1.0,
  "token_transfers": [],
  "unlimited_approval": false,
  "warnings": []
}
```

### POST /score

Run simulation and risk scoring without making a policy decision.

**Response:**

```json
{
  "score": 0.55,
  "reason_codes": ["HIGH_VALUE", "NEW_RECIPIENT"],
  "details": {
    "value_risk": 0.3,
    "recipient_risk": 0.25,
    "approval_risk": 0.0,
    "reputation_risk": 0.0,
    "simulation_risk": 0.0,
    "token_transfer_risk": 0.0
  }
}
```

### POST /attest

Sign an EIP-712 attestation for a policy decision. Call this after `/decide` returns a non-DENY decision. The attestation is what the smart contract verifies on-chain.

```bash
curl -X POST http://localhost:8000/attest \
  -H "Content-Type: application/json" \
  -d '{
    "target": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    "value": "1000000000000000000",
    "data": "0x",
    "nonce": 0,
    "decision": 0,
    "expiry": 1700000000
  }'
```

**Request Body:**

| Field | Type | Description |
|:------|:-----|:------------|
| `target` | string | Transaction target address |
| `value` | string | Wei value |
| `data` | string | Hex-encoded calldata |
| `nonce` | integer | Current wallet nonce (from contract) |
| `decision` | integer | Decision enum: 0=ALLOW, 1=GUARDIAN, 2=DELAY, 3=DENY |
| `expiry` | integer | Unix timestamp when the attestation expires |

**Response:**

```json
{
  "signature": "0x...",
  "signer": "0x...",
  "expiry": 1700000000
}
```

The default expiry is 1 hour from the time of signing if not specified.

### GET /audit-logs

Retrieve the audit trail of all policy decisions.

```bash
curl "http://localhost:8000/audit-logs?limit=10"
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|:----------|:-----|:--------|:------------|
| `limit` | integer | 50 | Maximum entries to return |

**Response:**

```json
[
  {
    "id": 1,
    "timestamp": "2024-01-15T10:30:00Z",
    "wallet_address": "0x1234...5678",
    "target_address": "0xabcd...ef01",
    "value": "1000000000000000000",
    "tx_type": "ETH_TRANSFER",
    "risk_score": 0.55,
    "decision": "REQUIRE_SECOND_SIGNATURE",
    "reason_codes": "HIGH_VALUE,NEW_RECIPIENT"
  }
]
```

### GET /health

Health check endpoint.

```bash
curl http://localhost:8000/health
```

```json
{
  "status": "ok"
}
```

## Admin Endpoints

### Known Recipients

Manage the set of trusted recipient addresses. Known recipients bypass the `NEW_RECIPIENT` risk penalty (+0.25).

```
GET    /admin/known-recipients              # List all known recipients
POST   /admin/known-recipients              # Add a recipient
DELETE /admin/known-recipients/{address}     # Remove a recipient
```

**POST Body:**

```json
{
  "address": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
}
```

### Allowlist

Manage the contract allowlist. Allowlisted contracts bypass the `UNKNOWN_CONTRACT` risk penalty (+0.3).

```
GET    /admin/allowlist              # List all allowlisted contracts
POST   /admin/allowlist              # Add to allowlist
DELETE /admin/allowlist/{address}     # Remove from allowlist
```

### Blocklist

Manage the contract blocklist. Transactions to blocklisted contracts always receive a score of 1.0 and a `DENY` decision.

```
GET    /admin/blocklist              # List all blocklisted contracts
POST   /admin/blocklist              # Add to blocklist
DELETE /admin/blocklist/{address}     # Remove from blocklist
```

## Error Responses

All endpoints return standard HTTP error codes with a JSON detail message:

```json
{
  "detail": "Error description"
}
```

| Code | Meaning |
|:-----|:--------|
| 400 | Bad request (invalid input) |
| 422 | Validation error (Pydantic schema mismatch) |
| 500 | Internal server error |

## CORS

CORS is enabled for all origins (`*`) in development. Restrict this to your frontend domain in production.
