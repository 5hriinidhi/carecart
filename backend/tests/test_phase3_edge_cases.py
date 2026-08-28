"""Phase 3 edge cases:

  1. OTP delivery failure from the provider -> clear 502, never a silent success
  2. same phone registering twice -> no duplicate account, no 500
  3. OCR on a non-medication image -> low confidence, no confident wrong answer
  4. over-long free-text fields -> 422 from server-side limits
  5. concurrent writes to one user's health profile -> one row, no 500
"""

from __future__ import annotations

import io
import shutil

import httpx
import pytest
from PIL import Image, ImageDraw, ImageFont
from sqlalchemy import text

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import HealthProfile, User
from app.services import ocr

BASE = "/api/v1"


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919333000001"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


@pytest.fixture
def user_id(db, auth) -> str:
    return db.execute(
        text("SELECT id FROM users WHERE phone_hash = :h"), {"h": hash_phone("+919333000001")}
    ).scalar_one()


# =============================================================== 1. OTP fails ==
def _use_http_provider(monkeypatch):
    monkeypatch.setattr(settings, "otp_provider_url", "https://sms.example/send")
    monkeypatch.setattr(settings, "otp_provider_api_key", "test-key")


def test_provider_transport_error_returns_clear_502(client, db, monkeypatch):
    _use_http_provider(monkeypatch)

    def _boom(*_a, **_kw):
        raise httpx.ConnectError("provider unreachable")

    monkeypatch.setattr("app.services.otp_sender.httpx.post", _boom)

    r = client.post(f"{BASE}/auth/request-otp", json={"phone": "+919333111111"})
    assert r.status_code == 502
    assert r.json()["detail"] and "try again" in r.json()["detail"].lower()
    # a failed send must not persist a challenge (would silently eat a rate slot)
    n = db.execute(
        text("SELECT count(*) FROM otp_challenges WHERE phone_e164 = :p"),
        {"p": "+919333111111"},
    ).scalar_one()
    assert n == 0


def test_provider_200_with_error_body_is_treated_as_failure(client, monkeypatch):
    _use_http_provider(monkeypatch)

    def _fake_post(url, **_kw):
        return httpx.Response(
            200, json={"status": "failed", "error": "insufficient balance"},
            request=httpx.Request("POST", url),
        )

    monkeypatch.setattr("app.services.otp_sender.httpx.post", _fake_post)
    r = client.post(f"{BASE}/auth/request-otp", json={"phone": "+919333222222"})
    assert r.status_code == 502


# ====================================================== 2. duplicate account ==
def test_returning_phone_does_not_create_a_second_user(client, db):
    phone = "+919333333333"
    # device 1 already has an account
    db.add(User(phone_hash=hash_phone(phone)))
    db.flush()

    code = client.post(f"{BASE}/auth/request-otp", json={"phone": phone}).json()["dev_code"]
    r = client.post(f"{BASE}/auth/verify-otp", json={"phone": phone, "code": code})
    assert r.status_code == 200
    assert r.json()["is_new_user"] is False

    n = db.execute(
        text("SELECT count(*) FROM users WHERE phone_hash = :h"), {"h": hash_phone(phone)}
    ).scalar_one()
    assert n == 1


def test_two_verify_otp_calls_for_a_new_phone_make_one_user(client, db):
    phone = "+919333444444"

    def _login():
        code = client.post(f"{BASE}/auth/request-otp", json={"phone": phone}).json()["dev_code"]
        return client.post(f"{BASE}/auth/verify-otp", json={"phone": phone, "code": code}).json()

    first = _login()
    second = _login()
    assert first["is_new_user"] is True
    assert second["is_new_user"] is False  # ON CONFLICT DO NOTHING -> no new row
    n = db.execute(
        text("SELECT count(*) FROM users WHERE phone_hash = :h"), {"h": hash_phone(phone)}
    ).scalar_one()
    assert n == 1


# ================================================= 3. OCR on a non-med image ==
_needs_tesseract = pytest.mark.skipif(
    shutil.which("tesseract") is None and not settings.tesseract_cmd,
    reason="tesseract binary not installed",
)


def _text_png(lines: list[str]) -> bytes:
    img = Image.new("RGB", (820, 90 + 70 * len(lines)), "white")
    draw = ImageDraw.Draw(img)
    for name in ("arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            font = ImageFont.truetype(name, 44)
            break
        except OSError:
            font = ImageFont.load_default(size=44)
    for i, line in enumerate(lines):
        draw.text((25, 25 + 70 * i), line, fill="black", font=font)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@_needs_tesseract
def test_non_medication_image_returns_low_confidence(client, auth):
    png = _text_png(["SUNSET BEACH RESORT", "Welcome Guests"])
    r = client.post(
        f"{BASE}/me/medications/scan",
        headers=auth,
        files={"file": ("sign.png", png, "image/png")},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["confirmation_required"] is True
    assert body["dosage_candidate"] is None
    # a non-label photo must NOT yield a confident guess
    assert body["name_candidate"] is None or body["name_confidence"] < 0.5


@_needs_tesseract
def test_blank_image_returns_no_candidate(client, auth):
    blank = io.BytesIO()
    Image.new("RGB", (400, 200), "white").save(blank, format="PNG")
    r = client.post(
        f"{BASE}/me/medications/scan", headers=auth,
        files={"file": ("blank.png", blank.getvalue(), "image/png")},
    )
    assert r.status_code == 200
    assert r.json()["name_candidate"] is None
    assert r.json()["name_confidence"] == 0.0


def test_guess_confidence_is_damped_without_medication_context():
    with_ctx = ocr.guess_medication("Amoxicillin 500 mg tablet", 0.85)
    without_ctx = ocr.guess_medication("Sunset Beach Resort Welcome Guests", 0.85)
    assert with_ctx.name_confidence > without_ctx.name_confidence
    assert without_ctx.name_confidence < 0.5


# ================================================ 4. over-long free text ==
def test_5000_char_condition_name_is_rejected(client, auth):
    r = client.post(
        f"{BASE}/me/conditions", headers=auth, json={"condition_name": "x" * 5000}
    )
    assert r.status_code == 422


def test_over_long_allergen_and_medication_are_rejected(client, auth):
    assert (
        client.post(
            f"{BASE}/me/allergies", headers=auth, json={"allergen_name": "y" * 5000}
        ).status_code
        == 422
    )
    assert (
        client.post(
            f"{BASE}/me/medications", headers=auth, json={"name": "z" * 5000}
        ).status_code
        == 422
    )


def test_body_metrics_rejects_junk_keys_and_absurd_numbers(client, auth):
    junk = client.put(
        f"{BASE}/me/health-profile",
        headers=auth,
        json={"body_metrics": {"weight": 70, "notes": "x" * 5000}},
    )
    assert junk.status_code == 422

    absurd = client.put(
        f"{BASE}/me/health-profile", headers=auth, json={"body_metrics": {"weight": 999999}}
    )
    assert absurd.status_code == 422


def test_diet_type_list_and_item_lengths_are_capped(client, auth):
    too_many = client.put(
        f"{BASE}/me/health-profile", headers=auth, json={"diet_type": ["tag"] * 100}
    )
    assert too_many.status_code == 422

    too_long = client.put(
        f"{BASE}/me/health-profile", headers=auth, json={"diet_type": ["v" * 5000]}
    )
    assert too_long.status_code == 422


# ============================================ 5. concurrent profile writes ==
def test_two_sequential_puts_leave_exactly_one_row(client, db, auth, user_id):
    client.put(
        f"{BASE}/me/health-profile",
        headers=auth,
        json={"gender": "female", "activity_level": "moderate"},
    )
    client.put(
        f"{BASE}/me/health-profile",
        headers=auth,
        json={"gender": "male", "activity_level": "heavy", "diet_type": ["low sodium"]},
    )

    got = client.get(f"{BASE}/me/health-profile", headers=auth).json()
    assert got["gender"] == "male" and got["activity_level"] == "heavy"
    assert got["diet_type"] == ["low sodium"]

    n = db.execute(
        text("SELECT count(*) FROM health_profiles WHERE user_id = :u"), {"u": user_id}
    ).scalar_one()
    assert n == 1


def test_put_when_a_row_already_exists_updates_instead_of_500(client, db, auth, user_id):
    # simulate "the other device already created the row" (a lost create race)
    db.add(HealthProfile(user_id=user_id, gender="female"))
    db.flush()

    r = client.put(
        f"{BASE}/me/health-profile",
        headers=auth,
        json={"gender": "male", "activity_level": "heavy"},
    )
    assert r.status_code == 200
    assert r.json()["gender"] == "male"

    n = db.execute(
        text("SELECT count(*) FROM health_profiles WHERE user_id = :u"), {"u": user_id}
    ).scalar_one()
    assert n == 1
