"""Database models and session management for audit logs."""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Float, Integer, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import settings


class Base(DeclarativeBase):
    pass


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    wallet = Column(String, nullable=False)
    target = Column(String, nullable=False)
    value = Column(String, nullable=False)
    tx_type = Column(String, nullable=False)
    risk_score = Column(Float, nullable=False)
    decision = Column(String, nullable=False)
    reason_codes = Column(String, nullable=False)  # JSON-encoded list


class PolicyConfig(Base):
    __tablename__ = "policy_configs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    key = Column(String, unique=True, nullable=False)
    value = Column(String, nullable=False)
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


engine = create_engine(settings.database_url, echo=False)
SessionLocal = sessionmaker(bind=engine)


def init_db():
    Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def log_decision(
    db: Session,
    wallet: str,
    target: str,
    value: str,
    tx_type: str,
    risk_score: float,
    decision: str,
    reason_codes: list[str],
):
    import json

    entry = AuditLog(
        wallet=wallet,
        target=target,
        value=value,
        tx_type=tx_type,
        risk_score=risk_score,
        decision=decision,
        reason_codes=json.dumps(reason_codes),
    )
    db.add(entry)
    db.commit()
