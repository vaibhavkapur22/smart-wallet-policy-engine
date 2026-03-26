from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel


class Decision(str, Enum):
    ALLOW = "ALLOW"
    REQUIRE_SECOND_SIGNATURE = "REQUIRE_SECOND_SIGNATURE"
    REQUIRE_DELAY = "REQUIRE_DELAY"
    DENY = "DENY"


class TransactionRequest(BaseModel):
    wallet: str
    chain_id: int
    target: str
    value: str  # wei as string
    data: str  # hex-encoded calldata


class SimulationResult(BaseModel):
    success: bool
    gas_used: int = 0
    eth_balance_delta: str = "0"
    token_transfers: list[dict] = []
    token_approvals: list[dict] = []
    has_unlimited_approval: bool = False
    assets_drained_pct: float = 0.0
    error: Optional[str] = None


class RiskScore(BaseModel):
    score: float  # 0.0 to 1.0
    reason_codes: list[str]
    details: dict = {}


class PolicyDecision(BaseModel):
    decision: Decision
    risk_score: float
    reason_codes: list[str]
    tx_type: str
    usd_value: float
    simulation: Optional[SimulationResult] = None


class AttestationRequest(BaseModel):
    wallet: str
    chain_id: int
    target: str
    value: str
    data: str
    nonce: int
    decision: Decision
    expiry: int


class AttestationResponse(BaseModel):
    op_hash: str
    signature: str
    decision: Decision
    expiry: int
    signer: str


class AuditLogEntry(BaseModel):
    timestamp: str
    wallet: str
    target: str
    value: str
    tx_type: str
    risk_score: float
    decision: Decision
    reason_codes: list[str]
