"""GET /me/medications/mapping — a stored medication -> drug class + the food
risk-compounds it interacts with (read-only, from the static tables)."""

from __future__ import annotations

import pytest

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import Medication, User
from scripts.load_risk_tables import load_all

BASE = "/api/v1/me/medications/mapping"


@pytest.fixture(scope="module", autouse=True)
def _rules(engine):
    from sqlalchemy.orm import Session

    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
        s.commit()


def _auth(db, phone: str = "+919955000001") -> tuple[User, dict]:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return u, {"Authorization": f"Bearer {create_access_token(u.id)}"}


def test_requires_auth(client):
    assert client.get(BASE).status_code == 401


def test_empty_when_no_meds(client, db):
    _, h = _auth(db)
    assert client.get(BASE, headers=h).json() == []


def test_resolves_class_and_interactions(client, db):
    u, h = _auth(db)
    db.add(Medication(user_id=u.id, name="Warfarin 5mg"))
    db.add(Medication(user_id=u.id, name="Zibblewockzine XR"))  # unknown
    db.flush()

    by_name = {m["name"]: m for m in client.get(BASE, headers=h).json()}

    w = by_name["Warfarin 5mg"]
    assert w["identified"] is True
    assert any("vitamin k" in c.lower() or "anticoagulant" in c.lower()
               for c in w["drug_classes"])
    assert any("vitamin k" in i.lower() for i in w["interactions"])

    unknown = by_name["Zibblewockzine XR"]
    assert unknown["identified"] is False
    assert unknown["drug_classes"] == [] and unknown["interactions"] == []


def test_mapping_path_is_not_swallowed_by_the_item_id_route(client, db):
    _, h = _auth(db)
    # "mapping" must hit the mapping route, not GET /me/medications/{uuid}
    assert client.get(BASE, headers=h).status_code == 200
