"""OTP challenge lifecycle: rate-limit, issue, verify.

The raw code is produced in :func:`issue_challenge`, returned to the caller
once (to hand to the sender), and never persisted or logged. Only its bcrypt
hash is stored.

Verification is deliberately opaque: "no live challenge", "wrong code" and
"too many attempts" all raise the same :class:`OtpError`, so a caller can't use
the endpoint to probe which phone numbers exist.
"""

from __future__ import annotations

import datetime as dt

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import hash_otp, random_numeric_code, verify_otp
from app.models import OtpChallenge


class RateLimited(Exception):
    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("too many OTP requests")
        self.retry_after_seconds = retry_after_seconds


class OtpError(Exception):
    """Generic verify failure — does not distinguish the cause on purpose."""


def _now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _aware(d: dt.datetime) -> dt.datetime:
    return d if d.tzinfo else d.replace(tzinfo=dt.UTC)


def purge_stale(db: Session) -> None:
    """Drop challenges older than a day — well outside any rate-limit window."""
    db.execute(delete(OtpChallenge).where(OtpChallenge.created_at < _now() - dt.timedelta(days=1)))


def _window_start() -> dt.datetime:
    return _now() - dt.timedelta(minutes=settings.otp_rate_window_minutes)


def count_recent_requests(db: Session, phone_e164: str) -> int:
    return (
        db.scalar(
            select(func.count())
            .select_from(OtpChallenge)
            .where(
                OtpChallenge.phone_e164 == phone_e164,
                OtpChallenge.created_at >= _window_start(),
            )
        )
        or 0
    )


def issue_challenge(db: Session, phone_e164: str) -> str:
    """Rate-limit, create a challenge row, and return the raw code.

    Caller must hand the code to the sender and then discard it. Raises
    :class:`RateLimited` when the phone has hit ``otp_max_per_window`` requests
    inside ``otp_rate_window_minutes``.
    """
    if count_recent_requests(db, phone_e164) >= settings.otp_max_per_window:
        oldest = db.scalar(
            select(func.min(OtpChallenge.created_at)).where(
                OtpChallenge.phone_e164 == phone_e164,
                OtpChallenge.created_at >= _window_start(),
            )
        )
        window_seconds = settings.otp_rate_window_minutes * 60
        retry_after = window_seconds
        if oldest is not None:
            elapsed = (_now() - _aware(oldest)).total_seconds()
            retry_after = max(1, int(window_seconds - elapsed))
        raise RateLimited(retry_after)

    code = random_numeric_code(settings.otp_length)
    db.add(
        OtpChallenge(
            phone_e164=phone_e164,
            code_hash=hash_otp(code),
            expires_at=_now() + dt.timedelta(minutes=settings.otp_ttl_minutes),
        )
    )
    db.flush()
    return code


def verify_challenge(db: Session, phone_e164: str, code: str) -> None:
    """Check ``code`` against the newest live challenge for ``phone_e164``.

    On success the challenge is consumed (single-use). On any failure raises
    :class:`OtpError`. Every call that finds a challenge increments its attempt
    counter; once ``otp_max_verify_attempts`` is reached the challenge is burned.
    """
    challenge = db.scalar(
        select(OtpChallenge)
        .where(
            OtpChallenge.phone_e164 == phone_e164,
            OtpChallenge.consumed_at.is_(None),
            OtpChallenge.expires_at > _now(),
        )
        .order_by(OtpChallenge.created_at.desc())
        .limit(1)
    )
    if challenge is None:
        raise OtpError

    if challenge.attempts >= settings.otp_max_verify_attempts:
        challenge.consumed_at = _now()
        db.flush()
        raise OtpError

    challenge.attempts += 1
    if not verify_otp(code, challenge.code_hash):
        db.flush()
        raise OtpError

    challenge.consumed_at = _now()
    db.flush()
