"""Rule-based risk scoring engine.

Evaluates transaction risk using configurable rules and returns
a score (0.0–1.0) with reason codes.
"""
from __future__ import annotations

from .models import RiskScore, SimulationResult, TransactionRequest
from .simulator import APPROVE_SELECTOR, TRANSFER_SELECTOR
from .config import settings

# In-memory stores for MVP (in production, use database)
known_recipients: set[str] = set()
allowlisted_contracts: set[str] = set()
blocked_contracts: set[str] = set()


def classify_tx_type(tx: TransactionRequest) -> str:
    """Classify the transaction type from calldata."""
    data = tx.data if tx.data else "0x"
    value_wei = int(tx.value) if tx.value else 0

    if data == "0x" or data == "" or len(data) < 10:
        return "ETH_TRANSFER" if value_wei > 0 else "EMPTY_CALL"

    selector = data[:10].lower()
    if selector == TRANSFER_SELECTOR:
        return "ERC20_TRANSFER"
    if selector == APPROVE_SELECTOR:
        return "ERC20_APPROVE"
    return "CONTRACT_CALL"


def estimate_usd_value(tx: TransactionRequest, tx_type: str) -> float:
    """Estimate the USD value of the transaction."""
    value_wei = int(tx.value) if tx.value else 0

    if tx_type == "ETH_TRANSFER":
        eth_amount = value_wei / 1e18
        return eth_amount * settings.eth_price_usd

    if tx_type == "ERC20_TRANSFER":
        data = tx.data
        if len(data) >= 138:
            amount = int(data[74:138], 16)
            # Assume stablecoin with 18 decimals for MVP
            return amount / 1e18
        return 0.0

    if tx_type == "ERC20_APPROVE":
        return 0.0  # Approvals don't move value directly

    # Generic contract call — use ETH value
    eth_amount = value_wei / 1e18
    return eth_amount * settings.eth_price_usd


def score_transaction(
    tx: TransactionRequest,
    simulation: SimulationResult,
    tx_type: str,
    usd_value: float,
) -> RiskScore:
    """Compute risk score based on rules."""
    risk = 0.0
    reasons: list[str] = []

    # Rule 1: Value-based risk
    if usd_value > settings.medium_risk_threshold_usd:
        risk += 0.3
        reasons.append("HIGH_VALUE")
    elif usd_value > settings.low_risk_threshold_usd:
        risk += 0.15
        reasons.append("MODERATE_VALUE")

    # Rule 2: New recipient
    target_lower = tx.target.lower()
    if target_lower not in known_recipients:
        risk += 0.25
        reasons.append("NEW_RECIPIENT")

    # Rule 3: Unlimited approval
    if simulation.has_unlimited_approval:
        risk += 0.4
        reasons.append("UNLIMITED_APPROVAL")

    # Rule 4: Contract reputation
    if target_lower in blocked_contracts:
        risk = 1.0
        reasons.append("BLOCKED_CONTRACT")
    elif tx_type in ("CONTRACT_CALL", "ERC20_APPROVE") and target_lower not in allowlisted_contracts:
        risk += 0.3
        reasons.append("UNKNOWN_CONTRACT")

    # Rule 5: Simulation red flags
    if simulation.assets_drained_pct > 0.5:
        risk = 1.0
        reasons.append("ASSETS_DRAINED")

    # Rule 6: Large token transfer
    if tx_type == "ERC20_TRANSFER" and usd_value > 5000:
        risk += 0.15
        reasons.append("LARGE_TOKEN_TRANSFER")

    # Clamp to [0, 1]
    risk = min(max(risk, 0.0), 1.0)

    return RiskScore(
        score=risk,
        reason_codes=reasons,
        details={
            "tx_type": tx_type,
            "usd_value": usd_value,
            "target": tx.target,
        },
    )
