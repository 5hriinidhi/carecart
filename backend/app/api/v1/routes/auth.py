"""Phone / OTP auth — matches the onboarding UI's login -> otp steps.

    POST /auth/request-otp   phone           -> 200, code sent (rate-limited 3 / 10 min / phone)
    POST /auth/verify-otp    phone + code    -> 200, { access_token, refresh_token, ... }
    POST /auth/refresh       refresh_token   -> 200, rotated token pair
    POST /auth/logout        refresh_token   -> 204

The raw OTP is never logged, in any environment.
"""

from __future__ import annotations

import datetime as dt
import logging

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.api.deps import DbSession
from app.core.config import settings
from app.core.security import (
    create_access_token,
    hash_phone,
    hash_token,
    mask_phone,
    new_refresh_token,
)
from app.models import RefreshToken, User
from app.schemas.auth import RefreshIn, RequestOtpIn, RequestOtpOut, TokenPair, VerifyOtpIn
from app.services import otp as otp_service
from app.services.otp_sender import OtpDeliveryError, get_otp_sender
from app.services.phone import InvalidPhoneNumber, normalize_e164

logger = logging.getLogger("carecart.auth")
router = APIRouter()

_GENERIC_CODE_ERROR = "That code is wrong or has expired. Request a new one."


def _aware(d: dt.datetime) -> dt.datetime:
    return d if d.tzinfo else d.replace(tzinfo=dt.UTC)


def _normalized(phone: str) -> str:
    try:
        return normalize_e164(phone)
    except InvalidPhoneNumber:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "Enter a valid phone number."
        ) from None


def _issue_token_pair(db: DbSession, user: User, *, is_new_user: bool) -> TokenPair:
    raw_refresh = new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hash_token(raw_refresh),
            expires_at=dt.datetime.now(dt.UTC)
            + dt.timedelta(minutes=settings.refresh_token_expire_minutes),
        )
    )
    return TokenPair(
        access_token=create_access_token(user.id),
        refresh_token=raw_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
        is_new_user=is_new_user,
    )


@router.post("/request-otp", response_model=RequestOtpOut)
def request_otp(body: RequestOtpIn, db: DbSession) -> RequestOtpOut:
    phone = _normalized(body.phone)
    otp_service.purge_stale(db)

    try:
        code = otp_service.issue_challenge(db, phone)
    except otp_service.RateLimited as limited:
        db.commit()  # keep the purge; nothing else was written
        minutes = max(1, limited.retry_after_seconds // 60)
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            f"Too many code requests for this number. Try again in about {minutes} minute(s).",
            headers={"Retry-After": str(limited.retry_after_seconds)},
        ) from None

    try:
        get_otp_sender().send(phone, code)
    except OtpDeliveryError:
        db.rollback()  # don't let a failed send burn a rate-limit slot
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Couldn't send the code right now. Please try again shortly.",
        ) from None

    db.commit()
    logger.info("otp requested for %s", mask_phone(phone))  # never the code
    return RequestOtpOut(
        detail="Verification code sent.",
        expires_in=settings.otp_ttl_minutes * 60,
        dev_code=code if settings.otp_echo_in_response else None,
    )


@router.post("/verify-otp", response_model=TokenPair)
def verify_otp(body: VerifyOtpIn, db: DbSession) -> TokenPair:
    phone = _normalized(body.phone)

    if not body.code.isdigit():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, _GENERIC_CODE_ERROR)

    try:
        otp_service.verify_challenge(db, phone, body.code)
    except otp_service.OtpError:
        db.commit()  # persist the attempt increment / burn
        raise HTTPException(status.HTTP_400_BAD_REQUEST, _GENERIC_CODE_ERROR) from None

    phone_hash = hash_phone(phone)
    # Race-safe get-or-create: a concurrent verify-otp for the same brand-new
    # number can't create a duplicate — the unique index on phone_hash makes the
    # second INSERT a no-op (ON CONFLICT DO NOTHING), and RETURNING tells us
    # whether *this* call was the one that created the row.
    inserted_id = db.scalar(
        pg_insert(User)
        .values(phone_hash=phone_hash)
        .on_conflict_do_nothing(index_elements=["phone_hash"])
        .returning(User.id)
    )
    is_new_user = inserted_id is not None
    user = db.scalar(select(User).where(User.phone_hash == phone_hash))
    if user is None:  # unreachable in practice
        db.rollback()
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Could not create the account.")
    if not user.is_active:
        db.commit()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This account is disabled.")

    pair = _issue_token_pair(db, user, is_new_user=is_new_user)
    db.commit()
    logger.info("otp verified for %s (new_user=%s)", mask_phone(phone), is_new_user)
    return pair


@router.post("/refresh", response_model=TokenPair)
def refresh(body: RefreshIn, db: DbSession) -> TokenPair:
    now = dt.datetime.now(dt.UTC)
    row = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_token(body.refresh_token))
    )
    if row is None or row.revoked_at is not None or _aware(row.expires_at) <= now:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired refresh token.")

    user = db.get(User, row.user_id)
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired refresh token.")

    row.revoked_at = now  # rotate: single-use refresh tokens
    pair = _issue_token_pair(db, user, is_new_user=False)
    db.commit()
    return pair


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(body: RefreshIn, db: DbSession) -> Response:
    row = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_token(body.refresh_token))
    )
    if row is not None and row.revoked_at is None:
        row.revoked_at = dt.datetime.now(dt.UTC)
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
