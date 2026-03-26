"""Policy engine — maps risk scores to authorization decisions."""

from .models import Decision, PolicyDecision, RiskScore, SimulationResult
from .config import settings


def decide(
    risk: RiskScore,
    tx_type: str,
    usd_value: float,
    simulation: SimulationResult,
) -> PolicyDecision:
    """Apply policy rules to determine the authorization decision."""

    # Hard deny conditions
    if "BLOCKED_CONTRACT" in risk.reason_codes:
        return _make_decision(Decision.DENY, risk, tx_type, usd_value, simulation)

    if "ASSETS_DRAINED" in risk.reason_codes:
        return _make_decision(Decision.DENY, risk, tx_type, usd_value, simulation)

    # Unlimited approval to unknown contract → deny
    if "UNLIMITED_APPROVAL" in risk.reason_codes and "UNKNOWN_CONTRACT" in risk.reason_codes:
        return _make_decision(Decision.DENY, risk, tx_type, usd_value, simulation)

    # Value-based thresholds
    if usd_value > settings.medium_risk_threshold_usd:
        return _make_decision(Decision.REQUIRE_DELAY, risk, tx_type, usd_value, simulation)

    if usd_value > settings.low_risk_threshold_usd:
        return _make_decision(
            Decision.REQUIRE_SECOND_SIGNATURE, risk, tx_type, usd_value, simulation
        )

    # High risk score regardless of value
    if risk.score >= 0.7:
        return _make_decision(Decision.REQUIRE_DELAY, risk, tx_type, usd_value, simulation)

    if risk.score >= 0.4:
        return _make_decision(
            Decision.REQUIRE_SECOND_SIGNATURE, risk, tx_type, usd_value, simulation
        )

    return _make_decision(Decision.ALLOW, risk, tx_type, usd_value, simulation)


def _make_decision(
    decision: Decision,
    risk: RiskScore,
    tx_type: str,
    usd_value: float,
    simulation: SimulationResult,
) -> PolicyDecision:
    return PolicyDecision(
        decision=decision,
        risk_score=risk.score,
        reason_codes=risk.reason_codes,
        tx_type=tx_type,
        usd_value=usd_value,
        simulation=simulation,
    )
