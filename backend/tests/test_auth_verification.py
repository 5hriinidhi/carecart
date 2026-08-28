"""Phase 3.1 verification — the five scenarios from the verification prompt.

  1. valid OTP request/verify cycle returns a working JWT
  2. an expired OTP is rejected
  3. an incorrect code is rejected
  4. a 4th OTP request within 10 minutes for the same number -> 429
  5. the raw OTP code never appears in the application logs from this run

Run:  pytest tests/test_auth_verification.py -v -s
"""

from __future__ import annotations

import logging

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import select, text

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.security import decode_access_token, hash_phone
from app.models import OtpChallenge

REQUEST = "/api/v1/auth/request-otp"
VERIFY = "/api/v1/auth/verify-otp"
PHONE = "+919876543210"


def _request_code(client, phone: str = PHONE) -> str:
    r = client.post(REQUEST, json={"phone": phone})
    assert r.status_code == 200, r.text
    return r.json()["dev_code"]


# ---------------------------------------------------------------------------
# 1. valid request/verify cycle -> a JWT that actually authenticates a request
# ---------------------------------------------------------------------------
def test_1_valid_cycle_returns_working_jwt(client, db):
    code = _request_code(client)
    r = client.post(VERIFY, json={"phone": PHONE, "code": code})
    assert r.status_code == 200, r.text
    body = r.json()

    access = body["access_token"]
    assert body["token_type"] == "bearer"
    assert body["refresh_token"] and body["refresh_token"] != access

    # the token is a valid access JWT
    payload = decode_access_token(access)
    assert payload["typ"] == "access"
    assert payload["sub"]

    # ...and it works: the real auth dependency resolves it to the right user
    user = get_current_user(
        db=db,
        creds=HTTPAuthorizationCredentials(scheme="Bearer", credentials=access),
    )
    assert str(user.id) == payload["sub"]
    assert user.phone_hash == hash_phone(PHONE)

    # a tampered token is refused
    with pytest.raises(HTTPException) as err:
        get_current_user(
            db=db,
            creds=HTTPAuthorizationCredentials(
                scheme="Bearer", credentials=access[:-3] + "xxx"
            ),
        )
    assert err.value.status_code == 401
    print(f"[1] verify-otp -> access JWT resolves to user {user.id} (phone {PHONE})")


# ---------------------------------------------------------------------------
# 2. expired OTP is rejected
# ---------------------------------------------------------------------------
def test_2_expired_otp_is_rejected(client, db):
    code = _request_code(client)
    db.execute(
        text(
            "UPDATE otp_challenges SET expires_at = now() - interval '1 second' "
            "WHERE phone_e164 = :p"
        ),
        {"p": PHONE},
    )
    db.flush()

    r = client.post(VERIFY, json={"phone": PHONE, "code": code})
    assert r.status_code == 400, r.text
    print(f"[2] expired code -> {r.status_code} {r.json()['detail']!r}")


# ---------------------------------------------------------------------------
# 3. incorrect code is rejected
# ---------------------------------------------------------------------------
def test_3_incorrect_code_is_rejected(client, db):
    real = _request_code(client)
    wrong = "000000" if real != "000000" else "111111"

    r = client.post(VERIFY, json={"phone": PHONE, "code": wrong})
    assert r.status_code == 400, r.text

    row = db.scalar(
        select(OtpChallenge)
        .where(OtpChallenge.phone_e164 == PHONE)
        .order_by(OtpChallenge.created_at.desc())
    )
    assert row.attempts == 1 and row.consumed_at is None  # counted, not burned
    print(f"[3] wrong code -> {r.status_code} {r.json()['detail']!r} (attempts={row.attempts})")


# ---------------------------------------------------------------------------
# 4. 4th request within the 10-minute window -> 429
# ---------------------------------------------------------------------------
def test_4_fourth_request_within_window_is_429(client):
    codes = []
    for i in range(settings.otp_max_per_window):
        r = client.post(REQUEST, json={"phone": PHONE})
        assert r.status_code == 200, f"request {i + 1} should succeed"
        codes.append(r.json()["dev_code"])

    r4 = client.post(REQUEST, json={"phone": PHONE})
    assert r4.status_code == 429, r4.text
    assert "Retry-After" in r4.headers and int(r4.headers["Retry-After"]) > 0
    print(
        f"[4] requests 1-{settings.otp_max_per_window} -> 200, "
        f"request {settings.otp_max_per_window + 1} -> {r4.status_code} "
        f"(Retry-After={r4.headers['Retry-After']}s)"
    )


# ---------------------------------------------------------------------------
# 5. the raw OTP never appears in the logs produced during this run
# ---------------------------------------------------------------------------
def test_5_raw_otp_never_appears_in_logs(client, caplog):
    cc_logger = logging.getLogger("carecart")
    cc_logger.addHandler(caplog.handler)
    caplog.set_level(logging.DEBUG)  # capture everything
    caplog.set_level(logging.DEBUG, logger="carecart")
    try:
        code = _request_code(client)
        r = client.post(VERIFY, json={"phone": PHONE, "code": code})
        assert r.status_code == 200
    finally:
        cc_logger.removeHandler(caplog.handler)

    captured = caplog.text
    print("---- application logs captured this run ----")
    for line in captured.strip().splitlines():
        print("  " + line)
    print("-------------------------------------------")

    # exact code, and any record field, must be clean
    assert code not in captured, f"raw OTP {code!r} leaked into the logs"
    for rec in caplog.records:
        blob = " ".join([str(rec.getMessage()), str(getattr(rec, "args", ""))])
        assert code not in blob, f"raw OTP {code!r} leaked into a log record"

    # and the number was masked, not printed in full
    assert PHONE not in captured
    print(f"[5] full request+verify cycle logged; raw code {code!r} absent from all log output")
