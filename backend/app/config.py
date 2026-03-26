from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Database
    database_url: str = "sqlite:///./policy_engine.db"

    # Ethereum
    rpc_url: str = "https://rpc.sepolia.org"
    chain_id: int = 11155111  # Sepolia
    wallet_contract_address: str = ""

    # Backend signer (trusted signer private key — keep secret)
    trusted_signer_private_key: str = ""

    # Policy defaults
    low_risk_threshold_usd: float = 100.0
    medium_risk_threshold_usd: float = 1000.0
    delay_duration_seconds: int = 3600

    # Simulation
    tenderly_api_key: str = ""
    tenderly_account: str = ""
    tenderly_project: str = ""

    # ETH price (simplified — in production, use an oracle)
    eth_price_usd: float = 3000.0

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
