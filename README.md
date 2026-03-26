# Smart Contract Wallet + Policy Engine

A smart contract wallet with a risk-based policy engine that simulates transactions, scores risk across six dimensions, and enforces tiered authorization on-chain via EIP-712 signed attestations.

> **[Read the full documentation](https://vaibhavkapur22.github.io/smart-wallet-policy-engine/)**

## Getting Started

```bash
# Clone with submodules (forge-std, openzeppelin)
git clone --recurse-submodules https://github.com/vaibhavkapur22/smart-wallet-policy-engine.git
cd smart-wallet-policy-engine
cp .env.example .env

# Build & test smart contract
forge build
forge test -vvv

# Start backend
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload

# Start frontend (separate terminal)
cd frontend
npm install
npm run dev
```

## Quick Example

```bash
# Evaluate a transaction against the policy engine
curl -X POST http://localhost:8000/decide \
  -H "Content-Type: application/json" \
  -d '{
    "from_address": "0x1234567890abcdef1234567890abcdef12345678",
    "to_address": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    "value": "50000000000000000",
    "data": "0x"
  }'

# Response: decision, risk score, reason codes, and simulation details
# {
#   "decision": "REQUIRE_SECOND_SIGNATURE",
#   "risk_score": 0.4,
#   "reason_codes": ["MEDIUM_VALUE", "NEW_RECIPIENT"],
#   "simulation": { "tx_type": "ETH_TRANSFER", "estimated_value_usd": 150.0, ... }
# }
```
