"""Phase 3 Check - full real user journey against the live app + DB + OCR.

request-otp -> verify-otp -> JWT -> submit the 6 onboarding steps -> scan a
medication label -> confirm & save -> fetch everything back and check every
field round-trips -> DELETE /me/account -> confirm via raw SQL that every row
for that user is physically gone (not soft-flagged), while a second user's rows
survive.

Run:  pytest tests/test_phase3_journey.py -v -s
"""

from __future__ import annotations

import io
import shutil

import pytest
from PIL import Image, ImageDraw, ImageFont
from sqlalchemy import text

from app.core.config import settings
from app.core.security import hash_phone

BASE = "/api/v1"

pytestmark = pytest.mark.skipif(
    shutil.which("tesseract") is None and not settings.tesseract_cmd,
    reason="tesseract binary not installed (journey includes a real label scan)",
)


def _font(size: int):
    for name in ("arialbd.ttf", "Arial.ttf", "DejaVuSans-Bold.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def _label_png(name: str = "TELMISARTAN", line2: str = "Tablets IP  40 mg") -> bytes:
    img = Image.new("RGB", (780, 240), "white")
    draw = ImageDraw.Draw(img)
    draw.text((30, 40), name, fill="black", font=_font(62))
    draw.text((30, 135), line2, fill="black", font=_font(34))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _row_count(db, table: str, column: str, value) -> int:
    return db.execute(
        text(f"SELECT count(*) FROM {table} WHERE {column} = :v"), {"v": value}
    ).scalar_one()


def _login(client, phone: str) -> dict:
    code = client.post(BASE + "/auth/request-otp", json={"phone": phone}).json()["dev_code"]
    r = client.post(BASE + "/auth/verify-otp", json={"phone": phone, "code": code})
    assert r.status_code == 200, r.text
    return r.json()


def test_full_user_journey_then_account_deletion(client, db):
    phone_a = "+919555000123"

    # ---- 1-2. request-otp -> verify-otp -> JWT ----
    tokens = _login(client, phone_a)
    assert tokens["is_new_user"] is True
    auth = {"Authorization": f"Bearer {tokens['access_token']}"}
    uid = db.execute(
        text("SELECT id FROM users WHERE phone_hash = :h"), {"h": hash_phone(phone_a)}
    ).scalar_one()
    print(f"  - auth: JWT issued, is_new_user=True, user_id={uid}")

    # ---- onboarding steps 1-4: gender, activity, body, diet ----
    hp_in = {
        "gender": "female",
        "activity_level": "moderate",
        "body_metrics": {"weight": 61.5, "height": 164, "weight_unit": "kg", "height_unit": "cm"},
        "diet_type": ["low sodium", "vegetarian"],
    }
    assert client.put(BASE + "/me/health-profile", headers=auth, json=hp_in).status_code == 200
    print("  - steps 1-4: PUT /me/health-profile OK")

    # ---- step 5: allergies ----
    for allergen in ("Peanuts", "Dairy"):
        assert (
            client.post(
                BASE + "/me/allergies", headers=auth, json={"allergen_name": allergen}
            ).status_code
            == 201
        )
    # conditions on file (health identity)
    for condition in ("Hypertension", "Type 2 diabetes"):
        assert (
            client.post(
                BASE + "/me/conditions", headers=auth, json={"condition_name": condition}
            ).status_code
            == 201
        )
    print("  - step 5: 2 allergies + 2 conditions saved")

    # ---- step 6: scan a real label photo, then confirm & save ----
    scan = client.post(
        BASE + "/me/medications/scan",
        headers=auth,
        files={"file": ("telma.png", _label_png(), "image/png")},
    )
    assert scan.status_code == 200, scan.text
    guess = scan.json()
    assert guess["confirmation_required"] is True
    assert guess["name_candidate"] and "TELMISARTAN" in guess["name_candidate"].upper()
    assert guess["dosage_candidate"] == "40 mg"
    assert client.get(BASE + "/me/medications", headers=auth).json() == []  # not auto-saved
    print(
        f"  - step 6: scan -> name={guess['name_candidate']!r} "
        f"dosage={guess['dosage_candidate']!r} conf={guess['name_confidence']} "
        f"(nothing saved yet)"
    )

    saved = client.post(
        BASE + "/me/medications",
        headers=auth,
        json={
            "name": guess["name_candidate"],
            "dosage": guess["dosage_candidate"],
            "active_from": "2026-03-01",
        },
    )
    assert saved.status_code == 201
    print("  - step 6: user confirmed -> POST /me/medications 201")

    # ---- fetch the full profile back: every field round-trips ----
    hp = client.get(BASE + "/me/health-profile", headers=auth).json()
    assert hp["gender"] == "female"
    assert hp["activity_level"] == "moderate"
    assert hp["body_metrics"] == hp_in["body_metrics"]
    assert hp["diet_type"] == ["low sodium", "vegetarian"]

    got_allergies = sorted(
        a["allergen_name"] for a in client.get(BASE + "/me/allergies", headers=auth).json()
    )
    assert got_allergies == ["Dairy", "Peanuts"]

    got_conditions = sorted(
        c["condition_name"] for c in client.get(BASE + "/me/conditions", headers=auth).json()
    )
    assert got_conditions == ["Hypertension", "Type 2 diabetes"]

    meds = client.get(BASE + "/me/medications", headers=auth).json()
    assert len(meds) == 1
    assert meds[0]["name"] == guess["name_candidate"]
    assert meds[0]["dosage"] == "40 mg"
    assert meds[0]["active_from"] == "2026-03-01"
    print("  - readback: health-profile, 2 allergies, 2 conditions, 1 medication all round-trip")

    # ---- a second user with their own data (must survive A's deletion) ----
    tokens_b = _login(client, "+919555000999")
    auth_b = {"Authorization": f"Bearer {tokens_b['access_token']}"}
    uid_b = db.execute(
        text("SELECT id FROM users WHERE phone_hash = :h"),
        {"h": hash_phone("+919555000999")},
    ).scalar_one()
    client.put(BASE + "/me/health-profile", headers=auth_b, json={"gender": "male"})
    client.post(BASE + "/me/conditions", headers=auth_b, json={"condition_name": "Asthma"})
    client.post(
        BASE + "/me/medications", headers=auth_b, json={"name": "Salbutamol", "dosage": "100 mcg"}
    )

    # ---- delete my account (user A) ----
    resp = client.delete(BASE + "/me/account", headers=auth)
    assert resp.status_code == 204
    # the test shares one Session across requests; production hands each request
    # a fresh one. Clear the identity map so the next lookups hit the DB.
    db.expunge_all()
    print("  - DELETE /me/account -> 204")

    # ---- raw SQL: every row for user A is physically gone ----
    counts_a = {
        "users": _row_count(db, "users", "id", uid),
        "health_profiles": _row_count(db, "health_profiles", "user_id", uid),
        "conditions": _row_count(db, "conditions", "user_id", uid),
        "allergies": _row_count(db, "allergies", "user_id", uid),
        "medications": _row_count(db, "medications", "user_id", uid),
        "refresh_tokens": _row_count(db, "refresh_tokens", "user_id", uid),
    }
    print(f"  - post-delete raw row counts for user A: {counts_a}")
    assert counts_a == {k: 0 for k in counts_a}, counts_a

    # not a soft flag: there is no users row at all to carry an is_active=false
    assert _row_count(db, "users", "id", uid) == 0

    # A's now-invalid token is rejected
    assert client.get(BASE + "/me/health-profile", headers=auth).status_code == 401

    # ---- user B is untouched ----
    counts_b = {
        "users": _row_count(db, "users", "id", uid_b),
        "health_profiles": _row_count(db, "health_profiles", "user_id", uid_b),
        "conditions": _row_count(db, "conditions", "user_id", uid_b),
        "medications": _row_count(db, "medications", "user_id", uid_b),
    }
    print(f"  - user B raw row counts (must survive): {counts_b}")
    assert counts_b == {"users": 1, "health_profiles": 1, "conditions": 1, "medications": 1}
    assert (
        client.get(BASE + "/me/conditions", headers=auth_b).json()[0]["condition_name"] == "Asthma"
    )
    print("  - user B data intact - deletion was correctly scoped to user A")
