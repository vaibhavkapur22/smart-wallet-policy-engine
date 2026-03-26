---
title: Deployment
layout: default
nav_order: 8
---

# Deployment Guide
{: .no_toc }

Deploying the smart contract, backend, and frontend to production environments.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Prerequisites

- **Foundry** -- Solidity compiler and deployment toolchain
- **Python** 3.10+ with pip
- **Node.js** 18+ with npm
- Funded deployer account on the target chain (ETH for gas)
- An Ethereum RPC provider (Alchemy, Infura, QuickNode)

## Environment Configuration

Copy `.env.example` and configure all values:

```bash
cp .env.example .env
```

### Smart Contract Variables

| Variable | Required | Description |
|:---------|:---------|:------------|
| `DEPLOYER_PRIVATE_KEY` | Yes | Private key of the deployer account |
| `WALLET_OWNER` | Yes | Address that will own the wallet |
| `TRUSTED_SIGNER` | Yes | Address matching the backend's signing key |
| `GUARDIAN` | Yes | Initial guardian address |
| `DELAY_DURATION` | No | Timelock period in seconds (default: 3600) |
| `SEPOLIA_RPC_URL` | Yes | RPC endpoint for deployment |

### Backend Variables

| Variable | Default | Description |
|:---------|:--------|:------------|
| `DATABASE_URL` | `sqlite:///./policy_engine.db` | SQLAlchemy connection string |
| `RPC_URL` | `https://rpc.sepolia.org` | Ethereum RPC for chain queries |
| `CHAIN_ID` | `11155111` | Target chain ID |
| `WALLET_CONTRACT_ADDRESS` | -- | Deployed wallet address (set after Step 1) |
| `TRUSTED_SIGNER_PRIVATE_KEY` | -- | Private key for signing attestations |
| `ETH_PRICE_USD` | `3000.0` | ETH price for USD estimation |
| `LOW_RISK_THRESHOLD_USD` | `100.0` | ALLOW/GUARDIAN threshold |
| `MEDIUM_RISK_THRESHOLD_USD` | `1000.0` | GUARDIAN/DELAY threshold |
| `DELAY_DURATION_SECONDS` | `3600` | Must match contract's `delayDuration` |

### Frontend Variables

| Variable | Description |
|:---------|:------------|
| `NEXT_PUBLIC_API_URL` | Backend API URL (e.g., `https://api.yourdomain.com`) |
| `NEXT_PUBLIC_WALLET_ADDRESS` | Deployed wallet contract address |
| `NEXT_PUBLIC_CHAIN_ID` | Target chain ID |

## Step 1: Deploy Smart Contract

### Build and Test

```bash
forge build
forge test -vvv
```

Ensure all 30+ tests pass before deploying.

### Deploy

```bash
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify
```

The script outputs the deployed contract address, owner, trusted signer, guardian, and delay duration. Save the contract address for Steps 2 and 3.

### Verify on Etherscan

If `--verify` fails automatically:

```bash
forge verify-contract <CONTRACT_ADDRESS> PolicySmartWallet \
    --chain sepolia \
    --constructor-args $(cast abi-encode \
        "constructor(address,address,address,uint256)" \
        $WALLET_OWNER $TRUSTED_SIGNER $GUARDIAN $DELAY_DURATION)
```

## Step 2: Deploy Backend

### Install Dependencies

```bash
cd backend
pip install -r requirements.txt
```

### Run in Development

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Run in Production

```bash
pip install gunicorn
gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

### Verify

```bash
curl http://localhost:8000/health
```

```json
{
  "status": "ok"
}
```

## Step 3: Deploy Frontend

### Build

```bash
cd frontend
npm install
npm run build
```

### Run

```bash
npm start
```

Or deploy to Vercel, Netlify, or any static hosting provider. Set the `NEXT_PUBLIC_*` environment variables in your hosting provider's dashboard.

## Production Checklist

### Security

- [ ] Store `TRUSTED_SIGNER_PRIVATE_KEY` in a secrets manager or HSM, not environment variables
- [ ] Restrict CORS to your frontend domain (currently allows all origins)
- [ ] Place admin endpoints (`/admin/*`) behind a VPN or internal network
- [ ] Enable TLS for all backend connections
- [ ] Never expose the trusted signer private key through any API
- [ ] Verify the backend signer address matches the contract's `trustedSigner`

### Reliability

- [ ] Run the backend behind a reverse proxy with health checks on `GET /health`
- [ ] Configure PostgreSQL instead of SQLite for production audit logs
- [ ] Set up monitoring for the backend process (systemd, Docker, or cloud service)
- [ ] Configure log aggregation for audit trail analysis
- [ ] Set up alerting on backend errors and downtime

### Smart Contract

- [ ] Verify the contract is verified on the block explorer
- [ ] Fund the wallet with ETH for gas (if it sends transactions)
- [ ] Configure on-chain allowlist with trusted contract addresses
- [ ] Configure on-chain blocklist with known malicious addresses
- [ ] Test all four decision paths end-to-end on testnet before mainnet

### Monitoring

- [ ] Monitor audit logs for unusual decision patterns (spike in DENYs or ALLOWs)
- [ ] Track risk score distribution over time
- [ ] Alert on backend signer key usage anomalies
- [ ] Monitor contract events (`Executed`, `OperationQueued`, `OperationCancelled`)
- [ ] Set up low-balance alerts for the wallet

## Scaling Considerations

| Component | Scalable? | Notes |
|:----------|:----------|:------|
| Backend API | Yes | Stateless; scale behind a load balancer |
| Audit Database | Yes | Migrate from SQLite to PostgreSQL for concurrent writes |
| Frontend | Yes | Static build; deploy to CDN |
| Smart Contract | N/A | Single instance per wallet; deploy multiple for multiple users |

### Throughput Bottlenecks

1. **Nonce serialization** -- The contract enforces strictly incrementing nonces, so transactions must be submitted sequentially per wallet
2. **Attestation signing** -- Single backend signer key; consider key rotation and HSM for high throughput
3. **RPC rate limits** -- Depends on provider plan; configure fallback endpoints
4. **SQLite concurrency** -- Single-writer limitation; migrate to PostgreSQL for production

## Network Support

The system is configured for **Sepolia testnet** (chain ID `11155111`). To deploy to a different network:

1. Update `CHAIN_ID` and `RPC_URL` in backend config
2. Update `NEXT_PUBLIC_CHAIN_ID` in frontend config
3. Use the appropriate RPC endpoint
4. Ensure the deployer and wallet owner have native tokens for gas
5. Update the EIP-712 domain automatically adapts via `block.chainid`
