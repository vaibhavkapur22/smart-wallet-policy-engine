"""EIP-712 attestation signing for policy decisions.

Signs operation data using the trusted backend signer key so the
smart contract can verify the decision on-chain.
"""

from __future__ import annotations

import time

from eth_account import Account
from eth_account.messages import encode_typed_data

from .config import settings
from .models import AttestationResponse, Decision

# EIP-712 domain — must match the smart contract's EIP712 constructor
DOMAIN = {
    "name": "PolicySmartWallet",
    "version": "1",
    "chainId": settings.chain_id,
    "verifyingContract": settings.wallet_contract_address or "0x0000000000000000000000000000000000000000",
}

TYPES = {
    "Operation": [
        {"name": "target", "type": "address"},
        {"name": "value", "type": "uint256"},
        {"name": "dataHash", "type": "bytes32"},
        {"name": "nonce", "type": "uint256"},
        {"name": "decision", "type": "uint8"},
        {"name": "expiry", "type": "uint256"},
    ],
}

DECISION_MAP = {
    Decision.ALLOW: 0,
    Decision.REQUIRE_SECOND_SIGNATURE: 1,
    Decision.REQUIRE_DELAY: 2,
    Decision.DENY: 3,
}


def sign_attestation(
    target: str,
    value: int,
    data_hash: str,
    nonce: int,
    decision: Decision,
    expiry: int | None = None,
    verifying_contract: str | None = None,
) -> AttestationResponse:
    """Sign an EIP-712 attestation for a policy decision."""
    if not settings.trusted_signer_private_key:
        raise ValueError("TRUSTED_SIGNER_PRIVATE_KEY not configured")

    if expiry is None:
        expiry = int(time.time()) + 3600  # 1 hour from now

    domain = {**DOMAIN}
    if verifying_contract:
        domain["verifyingContract"] = verifying_contract

    message = {
        "target": target,
        "value": value,
        "dataHash": bytes.fromhex(data_hash[2:] if data_hash.startswith("0x") else data_hash),
        "nonce": nonce,
        "decision": DECISION_MAP[decision],
        "expiry": expiry,
    }

    signable = encode_typed_data(
        domain_data=domain,
        types=TYPES,
        primary_type="Operation",
        message_data=message,
    )

    account = Account.from_key(settings.trusted_signer_private_key)
    signed = account.sign_message(signable)

    return AttestationResponse(
        op_hash=signed.messageHash.hex() if hasattr(signed, 'messageHash') else "0x",
        signature=signed.signature.hex(),
        decision=decision,
        expiry=expiry,
        signer=account.address,
    )
