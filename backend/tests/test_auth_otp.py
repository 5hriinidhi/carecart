"""Phase 3.1 — OTP auth + session management."""

from __future__ import annotations

import datetime as dt
import logging

import jwt
import pytest
from sqlalchemy import func, select, text

from app.core.config import settings
from app.core.security import decode_access_token, hash_phone, hash_token
from app.models import OtpChallenge, RefreshToken, User
from app.services.phone import InvalidPhoneNumber, normalize_e164

REQUEST = "/api/v1/auth/request-otp"
VERIFY = "/api/v1/auth/verify-otp"
REFRESH = "/api/v1/auth/refresh"
LOGOUT = "/api/v1/auth/logout"

PHONE = "+919876543210"


def _request_code(client, phone: str = PHONE) -> str:
    r = client.post(REQUEST, json={"phone": phone})
    assert r.status_code == 200, r.text
    code = r.json()["dev_code"]
    assert code is not None and code.isdigit() and len(code) == settings.otp_length
    return code


def _login(client, phone: str = PHONE) -> dict:
    code = _request_code(client, phone)
    r = client.post(VERIFY, json={"phone": phone, "code": code})
    assert r.status_code == 200, r.text
    return r.json()


# --------------------------------------------------------------- request-otp ---
def test_request_otp_returns_expiry_and_dev_code(client):
    r = client.post(REQUEST, json={"phone": PHONE})
    assert r.status_code == 200
    body = r.json()
    assert body["expires_in"] == settings.otp_ttl_minutes * 60
    assert body["dev_code"].isdigit() and len(body["dev_code"]) == 6
    assert body["detail"]


def test_request_otp_stores_only_a_hash(client, db):
    code = _request_code(client)
    row = db.scalar(select(OtpChallenge).where(OtpChallenge.phone_e164 == PHONE))
    assert row is not None
    assert row.code_hash != code
    assert code not in row.code_hash
    assert row.consumed_at is None
    assert row.attempts == 0


def test_request_otp_never_logs_the_raw_code(client, caplog):
    cc_logger = logging.getLogger("carecart")
    cc_logger.addHandler(caplog.handler)
    caplog.set_level(logging.DEBUG, logger="carecart")
    try:
        r = client.post(REQUEST, json={"phone": PHONE})
    finally:
        cc_logger.removeHandler(caplog.handler)

    code = r.json()["dev_code"]
    assert code not in caplog.text, "the raw OTP must never reach a log sink"
    # sanity: something *was* logged, and the phone number was masked
    assert "otp requested" in caplog.text
    assert PHONE not in caplog.text


def test_request_otp_rejects_a_bad_phone(client):
    r = client.post(REQUEST, json={"phone": "not-a-number"})
    assert r.status_code == 422


def test_request_otp_rate_limited_after_three_in_the_window(client):
    for _ in range(settings.otp_max_per_window):
        assert client.post(REQUEST, json={"phone": PHONE}).status_code == 200

    r = client.post(REQUEST, json={"phone": PHONE})
    assert r.status_code == 429
    assert "Retry-After" in r.headers
    assert int(r.headers["Retry-After"]) > 0
    assert "minute" in r.json()["detail"].lower()


def test_rate_limit_is_per_phone(client):
    for _ in range(settings.otp_max_per_window):
        client.post(REQUEST, json={"phone": PHONE})
    # a different number is unaffected
    assert client.post(REQUEST, json={"phone": "+919000000001"}).status_code == 200


def test_delivery_failure_rolls_back_and_does_not_burn_a_slot(client, db, monkeypatch):
    from app.services.otp_sender import OtpDeliveryError

    class _Boom:
        def send(self, *_a, **_kw):
            raise OtpDeliveryError("boom")

    monkeypatch.setattr("app.api.v1.routes.auth.get_otp_sender", lambda: _Boom())
    r = client.post(REQUEST, json={"phone": PHONE})
    assert r.status_code == 502
    # nothing persisted -> the rate-limit counter is untouched
    n = db.scalar(
        select(func.count()).select_from(OtpChallenge).where(OtpChallenge.phone_e164 == PHONE)
    )
    assert n == 0


# ---------------------------------------------------------------- verify-otp ---
def test_verify_otp_happy_path_issues_a_token_pair(client, db):
    tokens = _login(client)
    assert tokens["token_type"] == "bearer"
    assert tokens["is_new_user"] is True
    assert tokens["expires_in"] == settings.access_token_expire_minutes * 60

    payload = decode_access_token(tokens["access_token"])
    assert payload["typ"] == "access"

    user = db.scalar(select(User).where(User.phone_hash == hash_phone(PHONE)))
    assert user is not None and str(user.id) == payload["sub"]

    rt = db.scalar(select(RefreshToken).where(RefreshToken.user_id == user.id))
    assert rt is not None
    assert rt.token_hash == hash_token(tokens["refresh_token"])
    assert rt.token_hash != tokens["refresh_token"]
    assert rt.revoked_at is None


def test_verify_otp_consumes_the_challenge_single_use(client, db):
    code = _request_code(client)
    assert client.post(VERIFY, json={"phone": PHONE, "code": code}).status_code == 200
    # same code again -> rejected
    again = client.post(VERIFY, json={"phone": PHONE, "code": code})
    assert again.status_code == 400
    row = db.scalar(select(OtpChallenge).where(OtpChallenge.phone_e164 == PHONE))
    assert row.consumed_at is not None


def test_verify_otp_wrong_code_is_rejected_and_counts_an_attempt(client, db):
    _request_code(client)
    r = client.post(VERIFY, json={"phone": PHONE, "code": "000000"})
    assert r.status_code == 400
    row = db.scalar(select(OtpChallenge).where(OtpChallenge.phone_e164 == PHONE))
    assert row.attempts == 1
    assert row.consumed_at is None


def test_verify_otp_expired_code_is_rejected(client, db):
    code = _request_code(client)
    db.execute(
        text("UPDATE otp_challenges SET expires_at = now() - interval '1 minute' "
             "WHERE phone_e164 = :p"),
        {"p": PHONE},
    )
    db.flush()
    r = client.post(VERIFY, json={"phone": PHONE, "code": code})
    assert r.status_code == 400


def test_verify_otp_burns_the_code_after_max_attempts(client):
    code = _request_code(client)
    for _ in range(settings.otp_max_verify_attempts):
        assert client.post(VERIFY, json={"phone": PHONE, "code": "111111"}).status_code == 400
    # even the correct code no longer works
    assert client.post(VERIFY, json={"phone": PHONE, "code": code}).status_code == 400


def test_verify_otp_unknown_phone_gives_the_same_generic_error(client):
    r = client.post(VERIFY, json={"phone": "+919111111111", "code": "123456"})
    assert r.status_code == 400
    assert r.json()["detail"] == client.post(
        VERIFY, json={"phone": PHONE, "code": "123456"}
    ).json().get("detail")


def test_returning_user_is_not_flagged_new(client, db):
    _login(client)  # creates the user
    tokens = _login(client)  # second time
    assert tokens["is_new_user"] is False
    n = db.scalar(
        select(func.count()).select_from(User).where(User.phone_hash == hash_phone(PHONE))
    )
    assert n == 1


# -------------------------------------------------------------- refresh/logout --
def test_refresh_rotates_and_revokes_the_old_token(client):
    first = _login(client)
    r = client.post(REFRESH, json={"refresh_token": first["refresh_token"]})
    assert r.status_code == 200
    second = r.json()
    assert second["refresh_token"] != first["refresh_token"]
    assert second["access_token"] != first["access_token"]
    # the old refresh token is now dead
    assert client.post(REFRESH, json={"refresh_token": first["refresh_token"]}).status_code == 401


def test_refresh_rejects_garbage(client):
    assert client.post(REFRESH, json={"refresh_token": "x" * 40}).status_code == 401


def test_logout_revokes_the_refresh_token(client):
    tokens = _login(client)
    assert client.post(LOGOUT, json={"refresh_token": tokens["refresh_token"]}).status_code == 204
    assert client.post(REFRESH, json={"refresh_token": tokens["refresh_token"]}).status_code == 401


# --------------------------------------------------------------- unit helpers ---
@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("+919876543210", "+919876543210"),
        ("9876543210", "+919876543210"),
        ("09876543210", "+919876543210"),
        ("+91 98765-43210", "+919876543210"),
    ],
)
def test_normalize_e164(raw, expected):
    assert normalize_e164(raw) == expected


def test_normalize_e164_rejects_junk():
    for bad in ["", "abc", "+0123", "12345"]:
        with pytest.raises(InvalidPhoneNumber):
            normalize_e164(bad)


def test_decode_access_token_rejects_non_access_type():
    forged = jwt.encode(
        {
            "sub": "someone",
            "typ": "refresh",
            "exp": dt.datetime.now(dt.UTC) + dt.timedelta(minutes=5),
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(forged)
