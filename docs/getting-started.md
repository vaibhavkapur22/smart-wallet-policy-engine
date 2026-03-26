---
title: Getting Started
layout: default
nav_order: 2
---

# Getting Started
{: .no_toc }

Set up and run the Smart Contract Wallet + Policy Engine locally.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Prerequisites

- **Foundry** -- Solidity compiler and testing framework ([install](https://book.getfoundry.sh/getting-started/installation))
- **Python** 3.10+ with pip
- **Node.js** 18+ with npm
- **Git** with submodule support

## Clone the Repository

```bash
git clone --recurse-submodules https://github.com/vaibhavkapur22/smart-wallet-policy-engine.git
cd smart-wallet-policy-engine
```

If you already cloned without `--recurse-submodules`, fetch the dependencies manually:

```bash
git submodule update --init --recursive
```

This pulls `forge-std` and `openzeppelin-contracts` into `lib/`.

## Configure Environment

Copy the example environment file:

```bash
cp .env.example .env
```

For local development, fill in these values at minimum:

```bash
# Backend signer (generate a fresh keypair for testing)
TRUSTED_SIGNER_PRIVATE_KEY=0x...

# Contract address (set after deployment)
WALLET_CONTRACT_ADDRESS=0x...

# RPC (Sepolia testnet)
SEPOLIA_RPC_URL=https://rpc.sepolia.org
RPC_URL=https://rpc.sepolia.org
CHAIN_ID=11155111
```

See the [Configuration](/smart-wallet-policy-engine/deployment#environment-configuration) section for all available variables.

## Build and Test the Smart Contract

```bash
forge build
```

Run the full test suite (30+ tests):

```bash
forge test -vvv
```

Expected output: all tests pass, covering the ALLOW, REQUIRE_SECOND_SIGNATURE, REQUIRE_DELAY, and DENY paths, plus signature validation, replay protection, guardian management, and admin functions.

## Deploy the Smart Contract

Deploy to Sepolia testnet:

```bash
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast
```

The script reads `DEPLOYER_PRIVATE_KEY`, `WALLET_OWNER`, `TRUSTED_SIGNER`, `GUARDIAN`, and `DELAY_DURATION` from your `.env` file. It outputs the deployed contract address -- save this for the backend and frontend configuration.

## Start the Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

The API starts on `http://localhost:8000`.

Verify it's running:

```bash
curl http://localhost:8000/health
```

```json
{
  "status": "ok"
}
```

## Start the Frontend

```bash
cd frontend
npm install
npm run dev
```

The UI starts on `http://localhost:3000`.

## Make Your First Policy Decision

### 1. Evaluate a Transaction

Submit a transaction to the policy engine for risk assessment:

```bash
curl -X POST http://localhost:8000/decide \
  -H "Content-Type: application/json" \
  -d '{
    "from_address": "0x1234567890abcdef1234567890abcdef12345678",
    "to_address": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    "value": "50000000000000000",
    "data": "0x"
  }'
```

This sends 0.05 ETH (~$150) to an unknown address. The backend simulates the transaction, scores risk, and returns a decision:

```json
{
  "decision": "REQUIRE_SECOND_SIGNATURE",
  "risk_score": 0.4,
  "reason_codes": ["MEDIUM_VALUE", "NEW_RECIPIENT"],
  "simulation": {
    "tx_type": "ETH_TRANSFER",
    "estimated_value_usd": 150.0,
    "eth_balance_change": -0.05,
    "token_transfers": [],
    "unlimited_approval": false,
    "warnings": []
  }
}
```

The value ($150) exceeds the $100 threshold and the recipient is unknown, so the engine requires a guardian co-signature.

### 2. Request an Attestation

For non-DENY decisions, request an EIP-712 attestation that the smart contract can verify:

```bash
curl -X POST http://localhost:8000/attest \
  -H "Content-Type: application/json" \
  -d '{
    "target": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    "value": "50000000000000000",
    "data": "0x",
    "nonce": 0,
    "decision": 1,
    "expiry": 1700000000
  }'
```

```json
{
  "signature": "0x...",
  "signer": "0x...",
  "expiry": 1700000000
}
```

### 3. Add a Known Recipient

Reduce the risk score for trusted addresses by adding them to the known recipients list:

```bash
curl -X POST http://localhost:8000/admin/known-recipients \
  -H "Content-Type: application/json" \
  -d '{"address": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"}'
```

Re-evaluating the same transaction now returns `ALLOW` because the new-recipient penalty no longer applies.

## What's Next

- [Architecture](/smart-wallet-policy-engine/architecture) -- Understand the three-tier design and transaction flows
- [Risk Engine](/smart-wallet-policy-engine/risk-engine) -- How the six scoring rules work
- [API Reference](/smart-wallet-policy-engine/api-reference) -- Full endpoint documentation
- [Smart Contract](/smart-wallet-policy-engine/smart-contract) -- Contract function reference
- [Deployment](/smart-wallet-policy-engine/deployment) -- Production deployment guide
