"""Password / OTP hashing, JWT access tokens, opaque refresh tokens.

Security notes for this module:
  * OTP codes and passwords are LOW entropy -> bcrypt (slow KDF, per-value salt).
  * Refresh tokens are HIGH entropy (48 random bytes) -> SHA-256 is enough and
    lets us index the hash for O(1) lookup / revocation.
  * `mask_phone` exists so callers never have to log a full phone number.
  * Nothing here logs anything - the raw OTP must never reach a log sink.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import secrets
from typing import Any

import bcrypt
import jwt

from app.core.config import settings

_ACCESS_TOKEN_TYPE = "access"


# --------------------------------------------------------------------- passwords
def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode(), hashed.encode())
    except ValueError:
        return False


# -------------------------------------------------------------------------- OTP
def random_numeric_code(length: int) -> str:
    """A cryptographically-random numeric string, zero-padded to `length`."""
    return "".join(str(secrets.randbelow(10)) for _ in range(length))


def hash_otp(code: str) -> str:
    return bcrypt.hashpw(code.encode(), bcrypt.gensalt()).decode()


def verify_otp(code: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(code.encode(), hashed.encode())
    except ValueError:
        return False


# --------------------------------------------------------------- phone identity
def hash_phone(phone_e164: str) -> str:
    """Keyed HMAC-SHA256 of an E.164 number -> hex. `users` stores only this,
    never the plaintext number. Keyed (peppered) so the small phone-number
    keyspace can't be brute-forced from a bare digest."""
    return hmac.new(
        settings.phone_hash_key.encode(), phone_e164.encode(), hashlib.sha256
    ).hexdigest()


# --------------------------------------------------------------- refresh tokens
def new_refresh_token() -> str:
    """Opaque, URL-safe, ~64 chars. Only the hash is stored server-side."""
    return secrets.token_urlsafe(48)


def hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


# ---------------------------------------------------------------- access tokens
def create_access_token(subject: str | int, extra: dict[str, Any] | None = None) -> str:
    now = dt.datetime.now(dt.UTC)
    payload: dict[str, Any] = {
        "sub": str(subject),
        "typ": _ACCESS_TOKEN_TYPE,
        "jti": secrets.token_urlsafe(9),  # unique per token (revocation lists, tracing)
        "iat": now,
        "exp": now + dt.timedelta(minutes=settings.access_token_expire_minutes),
    }
    if extra:
        payload.update(extra)
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict[str, Any]:
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    if payload.get("typ") != _ACCESS_TOKEN_TYPE:
        raise jwt.InvalidTokenError("not an access token")
    return payload


# --------------------------------------------------------------------- logging
def mask_phone(phone_e164: str) -> str:
    """`+919876543210` -> `+91••••••3210`. Use this for every log line that
    would otherwise carry a phone number."""
    if len(phone_e164) <= 4:
        return "•" * len(phone_e164)
    tail = 4
    head = 3 if phone_e164.startswith("+") else 2
    middle = "•" * (len(phone_e164) - head - tail)
    return phone_e164[:head] + middle + phone_e164[-tail:]
