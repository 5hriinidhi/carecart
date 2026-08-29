"""Phase 6.3 — server-side input validation on the write paths, so malformed /
hostile client input never reaches an (encrypted) column unvalidated.
"""

from __future__ import annotations

from app.core.security import create_access_token, hash_phone
from app.models import User

BASE = "/api/v1"


def _auth(db, phone: str) -> dict:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


# --------------------------------------------------------------- free-text vault
def test_condition_name_is_trimmed_and_control_chars_stripped(client, db):
    h = _auth(db, "+919611000001")
    r = client.post(f"{BASE}/me/conditions", headers=h,
                    json={"condition_name": "  Hyper\x00tension\t \n "})
    assert r.status_code == 201
    assert r.json()["condition_name"] == "Hypertension"


def test_whitespace_only_condition_is_rejected(client, db):
    h = _auth(db, "+919611000002")
    r = client.post(f"{BASE}/me/conditions", headers=h,
                    json={"condition_name": "   \t  "})
    assert r.status_code == 422


def test_allergen_collapses_internal_whitespace(client, db):
    h = _auth(db, "+919611000003")
    r = client.post(f"{BASE}/me/allergies", headers=h,
                    json={"allergen_name": "tree     nuts"})
    assert r.status_code == 201 and r.json()["allergen_name"] == "tree nuts"


def test_medication_active_to_before_active_from_is_422(client, db):
    h = _auth(db, "+919611000004")
    r = client.post(f"{BASE}/me/medications", headers=h, json={
        "name": "Warfarin", "active_from": "2026-06-01", "active_to": "2026-05-01",
    })
    assert r.status_code == 422


def test_medication_name_over_limit_is_422(client, db):
    h = _auth(db, "+919611000005")
    r = client.post(f"{BASE}/me/medications", headers=h,
                    json={"name": "x" * 201})
    assert r.status_code == 422


def test_health_profile_gender_is_lowercased_and_cleaned(client, db):
    h = _auth(db, "+919611000006")
    r = client.put(f"{BASE}/me/health-profile", headers=h,
                   json={"gender": "  FeMale  "})
    assert r.status_code == 200 and r.json()["gender"] == "female"


def test_body_metrics_out_of_range_is_422(client, db):
    h = _auth(db, "+919611000007")
    r = client.put(f"{BASE}/me/health-profile", headers=h,
                   json={"body_metrics": {"weight": 99999, "height": 170}})
    assert r.status_code == 422


# --------------------------------------------------------------- scan/verdict
def test_verdict_nutriments_map_is_bounded(client, db):
    """100 keys + one absurd magnitude → accepted but bounded, not passed
    through to the scoring engine as-is."""
    from app.schemas.scan import ScanVerdictIn

    parsed = ScanVerdictIn(
        ingredients=["Rolled oats"],
        nutriments={"sodium_mg_100g": 9.9e12, "salt_g_100g": -5e9}
        | {f"junk_{i}": float(i) for i in range(100)},
    )
    assert len(parsed.nutriments) <= 40
    assert parsed.nutriments["sodium_mg_100g"] == 1_000_000.0  # clamped high
    assert parsed.nutriments["salt_g_100g"] == -1_000.0        # clamped low

    h = _auth(db, "+919611000008")
    r = client.post(f"{BASE}/scan/verdict", headers=h, json={
        "ingredients": ["Rolled oats"],
        "nutriments": {f"junk_{i}": float(i) for i in range(100)},
    })
    assert r.status_code == 200


def test_verdict_rejects_a_non_digit_barcode(client, db):
    h = _auth(db, "+919611000009")
    r = client.post(f"{BASE}/scan/verdict", headers=h, json={
        "ingredients": ["Rolled oats"], "barcode": "not-a-barcode",
    })
    assert r.status_code == 422


def test_verdict_accepts_a_valid_barcode_and_no_barcode(client, db):
    h = _auth(db, "+919611000010")
    for bc in (None, "8901234567890"):
        r = client.post(f"{BASE}/scan/verdict", headers=h,
                        json={"ingredients": ["Rolled oats"], "barcode": bc})
        assert r.status_code == 200, bc


# --------------------------------------------------------------- auth
def test_request_otp_rejects_a_non_phone_string(client):
    r = client.post(f"{BASE}/auth/request-otp", json={"phone": "hello there!"})
    assert r.status_code == 422


def test_request_otp_accepts_national_and_e164(client):
    for p in ("9876500011", "+91 98765 00011"):
        r = client.post(f"{BASE}/auth/request-otp", json={"phone": p})
        assert r.status_code == 200, p
