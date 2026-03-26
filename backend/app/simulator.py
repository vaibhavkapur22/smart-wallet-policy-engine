"""Transaction simulation layer.

For MVP, this provides local decoding of common tx types (ETH transfer,
ERC20 transfer, ERC20 approve) and flags dangerous patterns.
In production, integrate Tenderly or a fork-based simulation.
"""

from .models import SimulationResult, TransactionRequest
from .config import settings

# ERC20 function selectors
TRANSFER_SELECTOR = "0xa9059cbb"
APPROVE_SELECTOR = "0x095ea7b3"
TRANSFER_FROM_SELECTOR = "0x23b872dd"

MAX_UINT256 = 2**256 - 1
# Threshold for "unlimited" approval (> 2^255)
UNLIMITED_THRESHOLD = 2**255


def simulate_transaction(tx: TransactionRequest) -> SimulationResult:
    """Simulate a transaction and return analysis results."""
    data = tx.data if tx.data else "0x"
    value_wei = int(tx.value) if tx.value else 0

    # Plain ETH transfer
    if data == "0x" or data == "" or len(data) < 10:
        return SimulationResult(
            success=True,
            eth_balance_delta=f"-{value_wei}",
        )

    selector = data[:10].lower()

    # ERC20 transfer(address,uint256)
    if selector == TRANSFER_SELECTOR and len(data) >= 138:
        recipient = "0x" + data[34:74]
        amount = int(data[74:138], 16)
        return SimulationResult(
            success=True,
            token_transfers=[{
                "token": tx.target,
                "from": tx.wallet,
                "to": recipient,
                "amount": str(amount),
            }],
        )

    # ERC20 approve(address,uint256)
    if selector == APPROVE_SELECTOR and len(data) >= 138:
        spender = "0x" + data[34:74]
        allowance = int(data[74:138], 16)
        is_unlimited = allowance >= UNLIMITED_THRESHOLD
        return SimulationResult(
            success=True,
            token_approvals=[{
                "token": tx.target,
                "spender": spender,
                "allowance": str(allowance),
                "unlimited": is_unlimited,
            }],
            has_unlimited_approval=is_unlimited,
        )

    # Generic contract call — can't decode without ABI
    return SimulationResult(
        success=True,
        eth_balance_delta=f"-{value_wei}" if value_wei > 0 else "0",
    )
