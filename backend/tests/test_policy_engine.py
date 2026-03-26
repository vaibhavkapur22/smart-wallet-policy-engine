"""Tests for the risk engine, policy engine, and simulator."""

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models import Decision, TransactionRequest
from app.risk_engine import (
    allowlisted_contracts,
    blocked_contracts,
    classify_tx_type,
    estimate_usd_value,
    known_recipients,
    score_transaction,
)
from app.simulator import simulate_transaction
from app.policy_engine import decide
from app.db import init_db

init_db()
client = TestClient(app)


# ──────────────────────────────────────────────
#  Fixtures
# ──────────────────────────────────────────────

@pytest.fixture(autouse=True)
def clean_state():
    """Reset in-memory stores between tests."""
    known_recipients.clear()
    allowlisted_contracts.clear()
    blocked_contracts.clear()
    yield


def make_tx(
    target="0x1234567890abcdef1234567890abcdef12345678",
    value="0",
    data="0x",
) -> TransactionRequest:
    return TransactionRequest(
        wallet="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        chain_id=11155111,
        target=target,
        value=value,
        data=data,
    )


# ERC20 transfer calldata: transfer(0xrecipient, 100e18)
ERC20_TRANSFER_DATA = (
    "0xa9059cbb"
    "0000000000000000000000001234567890abcdef1234567890abcdef12345678"
    "0000000000000000000000000000000000000000000000056bc75e2d63100000"  # 100e18
)

# ERC20 approve calldata: approve(spender, MAX_UINT256)
MAX_UINT_HEX = "f" * 64
ERC20_APPROVE_UNLIMITED = (
    "0x095ea7b3"
    "0000000000000000000000001234567890abcdef1234567890abcdef12345678"
    + MAX_UINT_HEX
)


# ──────────────────────────────────────────────
#  Simulator tests
# ──────────────────────────────────────────────

class TestSimulator:
    def test_eth_transfer(self):
        tx = make_tx(value="1000000000000000000")  # 1 ETH
        result = simulate_transaction(tx)
        assert result.success
        assert result.eth_balance_delta == "-1000000000000000000"

    def test_erc20_transfer(self):
        tx = make_tx(data=ERC20_TRANSFER_DATA)
        result = simulate_transaction(tx)
        assert result.success
        assert len(result.token_transfers) == 1
        assert result.token_transfers[0]["amount"] == str(100 * 10**18)

    def test_erc20_unlimited_approve(self):
        tx = make_tx(data=ERC20_APPROVE_UNLIMITED)
        result = simulate_transaction(tx)
        assert result.success
        assert result.has_unlimited_approval

    def test_empty_call(self):
        tx = make_tx(data="0x")
        result = simulate_transaction(tx)
        assert result.success


# ──────────────────────────────────────────────
#  Risk engine tests
# ──────────────────────────────────────────────

class TestRiskEngine:
    def test_classify_eth_transfer(self):
        tx = make_tx(value="1000000000000000000")
        assert classify_tx_type(tx) == "ETH_TRANSFER"

    def test_classify_erc20_transfer(self):
        tx = make_tx(data=ERC20_TRANSFER_DATA)
        assert classify_tx_type(tx) == "ERC20_TRANSFER"

    def test_classify_erc20_approve(self):
        tx = make_tx(data=ERC20_APPROVE_UNLIMITED)
        assert classify_tx_type(tx) == "ERC20_APPROVE"

    def test_new_recipient_increases_risk(self):
        tx = make_tx(value="1000000000000000")  # small value
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        assert "NEW_RECIPIENT" in risk.reason_codes

    def test_known_recipient_no_flag(self):
        target = "0x1234567890abcdef1234567890abcdef12345678"
        known_recipients.add(target.lower())
        tx = make_tx(target=target, value="1000000000000000")
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        assert "NEW_RECIPIENT" not in risk.reason_codes

    def test_blocked_contract_max_risk(self):
        target = "0x1234567890abcdef1234567890abcdef12345678"
        blocked_contracts.add(target.lower())
        tx = make_tx(target=target, data="0xdeadbeef00")
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        assert risk.score == 1.0
        assert "BLOCKED_CONTRACT" in risk.reason_codes

    def test_unlimited_approval_increases_risk(self):
        tx = make_tx(data=ERC20_APPROVE_UNLIMITED)
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        assert "UNLIMITED_APPROVAL" in risk.reason_codes
        assert risk.score >= 0.4


# ──────────────────────────────────────────────
#  Policy engine tests
# ──────────────────────────────────────────────

class TestPolicyEngine:
    def test_low_value_allow(self):
        tx = make_tx(value="10000000000000000")  # 0.01 ETH = ~$30
        known_recipients.add(tx.target.lower())
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        decision = decide(risk, tx_type, usd_value, sim)
        assert decision.decision == Decision.ALLOW

    def test_medium_value_requires_guardian(self):
        # 0.05 ETH = $150 (above $100 threshold)
        tx = make_tx(value="50000000000000000")
        known_recipients.add(tx.target.lower())
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        decision = decide(risk, tx_type, usd_value, sim)
        assert decision.decision == Decision.REQUIRE_SECOND_SIGNATURE

    def test_high_value_requires_delay(self):
        # 1 ETH = $3000 (above $1000 threshold)
        tx = make_tx(value="1000000000000000000")
        known_recipients.add(tx.target.lower())
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        decision = decide(risk, tx_type, usd_value, sim)
        assert decision.decision == Decision.REQUIRE_DELAY

    def test_blocked_contract_denied(self):
        target = "0x1234567890abcdef1234567890abcdef12345678"
        blocked_contracts.add(target.lower())
        tx = make_tx(target=target, data="0xdeadbeef00")
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        decision = decide(risk, tx_type, usd_value, sim)
        assert decision.decision == Decision.DENY

    def test_unlimited_approval_unknown_contract_denied(self):
        tx = make_tx(data=ERC20_APPROVE_UNLIMITED)
        sim = simulate_transaction(tx)
        tx_type = classify_tx_type(tx)
        usd_value = estimate_usd_value(tx, tx_type)
        risk = score_transaction(tx, sim, tx_type, usd_value)
        decision = decide(risk, tx_type, usd_value, sim)
        # ERC20_APPROVE with unknown contract + unlimited → DENY
        assert decision.decision == Decision.DENY


# ──────────────────────────────────────────────
#  API endpoint tests
# ──────────────────────────────────────────────

class TestAPI:
    def test_health(self):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_simulate_endpoint(self):
        resp = client.post("/simulate", json={
            "wallet": "0xaaa",
            "chain_id": 11155111,
            "target": "0xbbb",
            "value": "1000000000000000000",
            "data": "0x",
        })
        assert resp.status_code == 200
        assert resp.json()["success"] is True

    def test_decide_endpoint(self):
        resp = client.post("/decide", json={
            "wallet": "0xaaa",
            "chain_id": 11155111,
            "target": "0xbbb",
            "value": "10000000000000000",  # 0.01 ETH
            "data": "0x",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert "decision" in data
        assert "risk_score" in data

    def test_admin_known_recipients(self):
        resp = client.post("/admin/known-recipients?address=0xabc")
        assert resp.status_code == 200
        resp = client.get("/admin/known-recipients")
        assert "0xabc" in resp.json()["recipients"]

    def test_admin_blocklist(self):
        resp = client.post("/admin/blocklist?address=0xevil")
        assert resp.status_code == 200
        resp = client.get("/admin/blocklist")
        assert "0xevil" in resp.json()["contracts"]
