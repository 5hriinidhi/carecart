"""Phase 6.1 — one continuous end-to-end backend journey.

    signup (request-otp) → OTP verify → onboarding (health profile, allergies,
    conditions) → medication upload (label scan → confirm → save) → barcode scan
    → verdict → history → trends → nudge → account deletion

Runs against the real (test) database through the real HTTP app. The only
stubs are the two external boundaries a CI box can't provide: Open Food Facts
(`openfoodfacts.fetch_product`) and the OCR engine (`ocr.extract_text`) — the
OCR *parsing* (`guess_medication`, `parse_ingredients`) still runs for real.

After deletion, raw SQL proves every row for the user is physically gone
(hard delete, not a soft flag) — including the Phase 5 scan_history / nudges —
while a second user created mid-journey is untouched.

Run:  pytest tests/test_phase6_e2e.py -v -s
"""

from __future__ import annotations

import io

import pytest
from PIL import Image
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import hash_phone
from scripts.load_risk_tables import load_all

BASE = "/api/v1"
PHONE_A = "+919600000021"
PHONE_B = "+919600000099"

CRACKERS = "50000000000201"   # sodium — scanned 3x → the recurring pattern
CASHEW = "50000000000218"     # tree-nut allergen → hard stop
OATS = "50000000000225"       # clean → safe

_OFF = {
    CRACKERS: {
        "code": CRACKERS, "product_name": "Sea-Salt Crackers", "brands": "Britannia",
        "ingredients_text": "Iodised salt",
        "ingredients": [{"text": "Iodised salt"}],
        "nutriments": {"sodium_100g": 1.4},
    },
    CASHEW: {
        "code": CASHEW, "product_name": "Cashew Energy Bar", "brands": "Yogabar",
        "ingredients_text": "Roasted cashew, dates, cane sugar",
        "ingredients": [{"text": "Roasted cashew"}, {"text": "Dates"},
                        {"text": "Cane sugar"}],
        "nutriments": {"sugars_100g": 22},
    },
    OATS: {
        "code": OATS, "product_name": "Rolled Oats", "brands": "Quaker",
        "ingredients_text": "Whole grain rolled oats",
        "ingredients": [{"text": "Whole grain rolled oats"}],
        "nutriments": {"fiber_100g": 10, "sugars_100g": 1},
    },
}


@pytest.fixture(scope="module", autouse=True)
def _ref(engine):
    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
    yield


def _png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (760, 240), "white").save(buf, format="PNG")
    return buf.getvalue()


def _count(db, table: str, col: str, val) -> int:
    return db.execute(
        text(f"SELECT count(*) FROM {table} WHERE {col} = :v"), {"v": val}
    ).scalar_one()


def test_full_backend_journey_signup_to_account_deletion(client, db, monkeypatch):
    monkeypatch.setattr(
        "app.services.openfoodfacts.fetch_product", lambda bc: _OFF[bc]
    )
    monkeypatch.setattr(
        "app.services.ocr.extract_text",
        lambda _b: ("TELMISARTAN\nTablets IP  40 mg", 0.9),
    )

    # ═══ 1. signup: request-otp → verify-otp ═══════════════════════════
    otp = client.post(f"{BASE}/auth/request-otp", json={"phone": PHONE_A})
    assert otp.status_code == 200
    dev_code = otp.json()["dev_code"]
    assert dev_code, "dev build must echo the code so local/CI e2e works"

    verify = client.post(f"{BASE}/auth/verify-otp",
                         json={"phone": PHONE_A, "code": dev_code})
    assert verify.status_code == 200, verify.text
    tok = verify.json()
    assert tok["is_new_user"] is True                 # brand-new account
    H = {"Authorization": f"Bearer {tok['access_token']}"}
    refresh = tok["refresh_token"]

    uid = db.execute(
        text("SELECT id FROM users WHERE phone_hash = :h"),
        {"h": hash_phone(PHONE_A)},
    ).scalar_one()

    # ═══ 2. onboarding: health profile + allergies + conditions ═══════
    hp = {
        "gender": "female",
        "activity_level": "moderate",
        "body_metrics": {"weight": 62.0, "height": 165,
                         "weight_unit": "kg", "height_unit": "cm"},
        "diet_type": ["low sodium", "vegetarian"],
    }
    assert client.put(f"{BASE}/me/health-profile", headers=H, json=hp).status_code == 200
    for allergen in ("tree nuts", "dairy"):
        assert client.post(f"{BASE}/me/allergies", headers=H,
                           json={"allergen_name": allergen}).status_code == 201
    for cond in ("Hypertension", "Type 2 diabetes"):
        assert client.post(f"{BASE}/me/conditions", headers=H,
                           json={"condition_name": cond}).status_code == 201

    # ═══ 3. medication upload: label scan → confirm → save ════════════
    scan = client.post(f"{BASE}/me/medications/scan", headers=H,
                       files={"file": ("label.png", _png(), "image/png")})
    assert scan.status_code == 200, scan.text
    guess = scan.json()
    assert guess["confirmation_required"] is True
    assert guess["name_candidate"] and "TELMISARTAN" in guess["name_candidate"].upper()
    assert client.get(f"{BASE}/me/medications", headers=H).json() == []  # not auto-saved

    saved = client.post(f"{BASE}/me/medications", headers=H, json={
        "name": guess["name_candidate"],
        "dosage": guess["dosage_candidate"] or "40 mg",
        "active_from": "2026-01-01",
    })
    assert saved.status_code == 201
    # also on an anticoagulant (drives a real drug-interaction path)
    assert client.post(f"{BASE}/me/medications", headers=H,
                       json={"name": "Warfarin 5mg"}).status_code == 201

    # ═══ 4. barcode scan → verdict  (the real client flow) ═══════════
    tiers: list[str] = []
    nudge_on_scan: list[tuple[str, int]] = []

    def scan_and_score(barcode: str) -> dict:
        p = client.get(f"{BASE}/products/{barcode}", headers=H)
        assert p.status_code == 200, p.text
        prod = p.json()
        v = client.post(f"{BASE}/scan/verdict", headers=H, json={
            "ingredients": prod["ingredients"],
            "nutriments": prod["nutriments"],
            "barcode": barcode,
            "product_name": prod["name"],
        })
        assert v.status_code == 200, v.text
        b = v.json()
        tiers.append(b["tier"])
        if b["nudge"]:
            nudge_on_scan.append((b["nudge"]["factor"], b["nudge"]["hit_count"]))
        return b

    v_cr1 = scan_and_score(CRACKERS)                       # sodium hit 1
    v_nut = scan_and_score(CASHEW)                         # allergen
    v_oat = scan_and_score(OATS)                           # clean
    scan_and_score(CRACKERS)                               # sodium hit 2 (cache)
    scan_and_score(CRACKERS)                               # sodium hit 3 → nudge

    # a salty cracker for a hypertensive on an ARB + anticoagulant is non-safe
    # (ceiling + a real drug-interaction deduction) — exact caution vs avoid is
    # the model's call; what matters is it's flagged and it's about sodium.
    assert v_cr1["tier"] in ("caution", "avoid")
    assert any(r["kind"] in ("condition_ceiling", "drug_interaction")
               and r.get("factor") == "sodium" for r in v_cr1["reasons"])
    assert v_nut["hard_stop"] is True and v_nut["tier"] == "avoid" and v_nut["score"] == 0
    assert v_nut["reasons"][0]["kind"] == "allergen"
    assert v_oat["tier"] == "safe"
    assert nudge_on_scan == [("sodium", 3)]

    # ═══ 5. history — every verdict auto-logged ══════════════════════
    hist = client.get(f"{BASE}/history", headers=H, params={"limit": 100}).json()
    assert hist["total"] == 5
    from collections import Counter
    hist_tiers = Counter(it["tier"] for it in hist["items"])
    assert hist_tiers == Counter(tiers)                    # history == verdict tiers
    assert hist_tiers["safe"] == 1                         # only the oats
    assert hist_tiers["caution"] + hist_tiers["avoid"] == 4
    assert [it["product_name"] for it in hist["items"]][0] == "Sea-Salt Crackers"

    # ═══ 6. trends — aggregates agree with history ═══════════════════
    tr = client.get(f"{BASE}/analytics/trends", headers=H, params={"tz": "UTC"}).json()
    assert tr["total_scans"] == 5
    for t in ("safe", "caution", "avoid"):
        assert sum(w[t] for w in tr["weekly"]) == hist_tiers[t]
        assert sum(m[t] for m in tr["monthly"]) == hist_tiers[t]
    assert 1 <= tr["diet_health_score"] <= 100

    # ═══ 7. nudge — the recurring sodium pattern, grounded ══════════
    nd = client.get(f"{BASE}/nudges", headers=H).json()
    assert len(nd["items"]) == 1
    n = nd["items"][0]
    assert n["factor"] == "sodium" and n["hit_count"] == 3
    assert "odium" in n["message"] and len(n["message"]) > 40
    grounded = [
        it for it in hist["items"]
        if it["tier"] in ("caution", "avoid")
        and any(kr.get("factor") == "sodium" for kr in it["key_reasons"])
    ]
    assert len(grounded) >= 3

    # ── a second user, created mid-journey, with their own data ──────
    dev_b = client.post(f"{BASE}/auth/request-otp", json={"phone": PHONE_B}).json()["dev_code"]
    tok_b = client.post(f"{BASE}/auth/verify-otp",
                        json={"phone": PHONE_B, "code": dev_b}).json()
    H_B = {"Authorization": f"Bearer {tok_b['access_token']}"}
    uid_b = db.execute(
        text("SELECT id FROM users WHERE phone_hash = :h"), {"h": hash_phone(PHONE_B)}
    ).scalar_one()
    client.put(f"{BASE}/me/health-profile", headers=H_B, json={"gender": "male"})
    client.post(f"{BASE}/me/conditions", headers=H_B, json={"condition_name": "Asthma"})
    scan_b = client.get(f"{BASE}/products/{OATS}", headers=H_B).json()
    client.post(f"{BASE}/scan/verdict", headers=H_B, json={
        "ingredients": scan_b["ingredients"], "nutriments": scan_b["nutriments"],
        "barcode": OATS, "product_name": scan_b["name"],
    })
    assert client.get(f"{BASE}/history", headers=H_B).json()["total"] == 1

    # ═══ 8. account deletion — hard delete, correctly scoped ════════
    assert client.delete(f"{BASE}/me/account", headers=H).status_code == 204
    db.expunge_all()  # shared test session — force the next reads to hit the DB

    tables = ("users", "health_profiles", "conditions", "allergies", "medications",
              "refresh_tokens", "scan_history", "nudges")
    cols = {"users": "id"}
    after = {t: _count(db, t, cols.get(t, "user_id"), uid) for t in tables}
    assert after == {t: 0 for t in tables}, after          # nothing left, no soft flag

    # the deleted user's tokens no longer work
    assert client.get(f"{BASE}/me/health-profile", headers=H).status_code == 401
    assert client.post(f"{BASE}/auth/refresh",
                       json={"refresh_token": refresh}).status_code == 401

    # user B is entirely untouched
    assert _count(db, "users", "id", uid_b) == 1
    assert _count(db, "scan_history", "user_id", uid_b) == 1
    assert client.get(f"{BASE}/me/conditions", headers=H_B).json()[0]["condition_name"] == "Asthma"

    print("\n============ Phase 6.1 backend E2E ============")
    print(f"user A journey: signup → onboarding → med upload → 5 scans "
          f"→ history({hist['total']}) → trends(DHS {tr['diet_health_score']}) "
          f"→ nudge({n['factor']}) → account deleted")
    print(f"post-delete row counts for user A: {after}")
    print("user B untouched — deletion scoped correctly")
