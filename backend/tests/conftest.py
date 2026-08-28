"""Shared test fixtures.

DB-backed tests run against a DEDICATED, freshly-created ``<db>_test`` database
(dropped and recreated per session) so they never see dev / smoke-test data and
never pollute the dev database. Each test then runs inside a transaction that is
rolled back on teardown. If no Postgres is reachable the DB tests are skipped.
"""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

import app.models  # noqa: F401  registers every table on Base.metadata
from app.core.config import settings
from app.db.base import Base
from app.db.session import get_db
from app.main import app


def _split_url() -> tuple[str, str]:
    """(prefix, dbname) from the configured SQLAlchemy URL."""
    prefix, dbname = settings.sqlalchemy_url.rsplit("/", 1)
    return prefix, dbname


@pytest.fixture(scope="session")
def engine() -> Iterator[Engine]:
    prefix, dbname = _split_url()
    test_db = f"{dbname}_test"
    admin_url = f"{prefix}/postgres"

    admin = create_engine(admin_url, isolation_level="AUTOCOMMIT", future=True)
    try:
        with admin.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001
        admin.dispose()
        pytest.skip(f"Postgres not reachable ({exc.__class__.__name__}); skipping DB tests")

    with admin.connect() as conn:
        conn.execute(text(f'DROP DATABASE IF EXISTS "{test_db}" WITH (FORCE)'))
        conn.execute(text(f'CREATE DATABASE "{test_db}"'))
    admin.dispose()

    eng = create_engine(f"{prefix}/{test_db}", future=True, pool_pre_ping=True)
    Base.metadata.create_all(bind=eng)
    yield eng
    eng.dispose()

    admin = create_engine(admin_url, isolation_level="AUTOCOMMIT", future=True)
    with admin.connect() as conn:
        conn.execute(text(f'DROP DATABASE IF EXISTS "{test_db}" WITH (FORCE)'))
    admin.dispose()


@pytest.fixture
def db(engine: Engine) -> Iterator[Session]:
    """A session on its own connection+transaction, rolled back on teardown.

    ``join_transaction_mode="create_savepoint"`` makes the route code's
    ``session.commit()`` release a SAVEPOINT instead of committing for real, so
    the outer rollback still wipes everything the test did.
    """
    connection = engine.connect()
    outer = connection.begin()
    TestSession = sessionmaker(
        bind=connection,
        future=True,
        expire_on_commit=False,
        join_transaction_mode="create_savepoint",
    )
    session = TestSession()
    try:
        yield session
    finally:
        session.close()
        outer.rollback()
        connection.close()


@pytest.fixture
def client(db: Session) -> Iterator[TestClient]:
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.pop(get_db, None)
