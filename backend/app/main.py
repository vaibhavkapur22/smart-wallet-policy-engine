"""FastAPI backend for the Policy Smart Wallet risk/policy engine."""

import json
import time
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from Crypto.Hash import keccak as keccak_mod

from .attestations import sign_attestation
from .config import settings
from .db import AuditLog, get_db, init_db, log_decision
from .models import (
    AttestationRequest,
    AttestationResponse,
    Decision,
    PolicyDecision,
    RiskScore,
    SimulationResult,
    TransactionRequest,
)
from .policy_engine import decide
from .risk_engine import (
    allowlisted_contracts,
    blocked_contracts,
    classify_tx_type,
    estimate_usd_value,
    known_recipients,
    score_transaction,
)
from .simulator import simulate_transaction

app = FastAPI(
    title="Policy Smart Wallet — Risk & Policy Engine",
    version="1.0.0",
    description="Off-chain risk scoring, policy decisions, and attestation signing for the PolicySmartWallet.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup():
    init_db()


# ──────────────────────────────────────────────
#  Core endpoints
# ──────────────────────────────────────────────


@app.post("/simulate", response_model=SimulationResult)
def simulate(tx: TransactionRequest):
    """Simulate a transaction and return impact analysis."""
    return simulate_transaction(tx)


@app.post("/score", response_model=RiskScore)
def score(tx: TransactionRequest):
    """Score a transaction's risk level."""
    simulation = simulate_transaction(tx)
    tx_type = classify_tx_type(tx)
    usd_value = estimate_usd_value(tx, tx_type)
    return score_transaction(tx, simulation, tx_type, usd_value)


@app.post("/decide", response_model=PolicyDecision)
def decide_endpoint(tx: TransactionRequest, db: Session = Depends(get_db)):
    """Run full pipeline: simulate → score → decide. Returns policy decision."""
    simulation = simulate_transaction(tx)
    tx_type = classify_tx_type(tx)
    usd_value = estimate_usd_value(tx, tx_type)
    risk = score_transaction(tx, simulation, tx_type, usd_value)
    decision = decide(risk, tx_type, usd_value, simulation)

    # Audit log
    log_decision(
        db=db,
        wallet=tx.wallet,
        target=tx.target,
        value=tx.value,
        tx_type=tx_type,
        risk_score=risk.score,
        decision=decision.decision.value,
        reason_codes=risk.reason_codes,
    )

    return decision


@app.post("/attest", response_model=AttestationResponse)
def attest(req: AttestationRequest):
    """Sign a policy attestation for on-chain verification."""
    # Hash the calldata
    data_bytes = bytes.fromhex(req.data[2:] if req.data.startswith("0x") else req.data) if req.data else b""
    k = keccak_mod.new(digest_bits=256)
    k.update(data_bytes)
    data_hash = "0x" + k.hexdigest()

    return sign_attestation(
        target=req.target,
        value=int(req.value),
        data_hash=data_hash,
        nonce=req.nonce,
        decision=req.decision,
        expiry=req.expiry if req.expiry > 0 else None,
        verifying_contract=req.wallet,
    )


# ──────────────────────────────────────────────
#  Admin endpoints
# ──────────────────────────────────────────────


@app.get("/audit-logs")
def get_audit_logs(limit: int = 50, db: Session = Depends(get_db)):
    """Retrieve recent audit log entries."""
    logs = db.query(AuditLog).order_by(AuditLog.id.desc()).limit(limit).all()
    return [
        {
            "id": log.id,
            "timestamp": log.timestamp.isoformat() if log.timestamp else None,
            "wallet": log.wallet,
            "target": log.target,
            "value": log.value,
            "tx_type": log.tx_type,
            "risk_score": log.risk_score,
            "decision": log.decision,
            "reason_codes": json.loads(log.reason_codes),
        }
        for log in logs
    ]


@app.post("/admin/known-recipients")
def add_known_recipient(address: str):
    """Add a known recipient address."""
    known_recipients.add(address.lower())
    return {"status": "added", "address": address.lower()}


@app.delete("/admin/known-recipients")
def remove_known_recipient(address: str):
    """Remove a known recipient address."""
    known_recipients.discard(address.lower())
    return {"status": "removed", "address": address.lower()}


@app.get("/admin/known-recipients")
def list_known_recipients():
    """List all known recipients."""
    return {"recipients": list(known_recipients)}


@app.post("/admin/allowlist")
def add_to_allowlist(address: str):
    """Add a contract to the allowlist."""
    allowlisted_contracts.add(address.lower())
    return {"status": "added", "address": address.lower()}


@app.delete("/admin/allowlist")
def remove_from_allowlist(address: str):
    """Remove a contract from the allowlist."""
    allowlisted_contracts.discard(address.lower())
    return {"status": "removed", "address": address.lower()}


@app.get("/admin/allowlist")
def list_allowlist():
    """List all allowlisted contracts."""
    return {"contracts": list(allowlisted_contracts)}


@app.post("/admin/blocklist")
def add_to_blocklist(address: str):
    """Add a contract to the blocklist."""
    blocked_contracts.add(address.lower())
    return {"status": "added", "address": address.lower()}


@app.delete("/admin/blocklist")
def remove_from_blocklist(address: str):
    """Remove a contract from the blocklist."""
    blocked_contracts.discard(address.lower())
    return {"status": "removed", "address": address.lower()}


@app.get("/admin/blocklist")
def list_blocklist():
    """List all blocked contracts."""
    return {"contracts": list(blocked_contracts)}


@app.get("/health")
def health():
    return {"status": "ok", "chain_id": settings.chain_id}
