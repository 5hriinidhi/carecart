"""Auth API payloads for the onboarding login -> otp flow."""

from __future__ import annotations

import re

from pydantic import BaseModel, Field, field_validator

# digits, with an optional leading + and separators — must carry 8–15 digits
_PHONE_SHAPE = re.compile(r"^\+?[\d][\d\s().-]{6,20}$")


class RequestOtpIn(BaseModel):
    phone: str = Field(
        ...,
        min_length=6,
        max_length=24,
        examples=["+919876543210", "9876543210"],
        description="Phone number in E.164, or a national number for the default country code.",
    )

    @field_validator("phone")
    @classmethod
    def _phone_shape(cls, v: str) -> str:
        v = v.strip()
        digits = re.sub(r"\D", "", v)
        if not _PHONE_SHAPE.match(v) or not (8 <= len(digits) <= 15):
            raise ValueError("that doesn't look like a phone number")
        return v


class RequestOtpOut(BaseModel):
    detail: str
    expires_in: int = Field(..., description="Seconds until the code expires.")
    dev_code: str | None = Field(
        default=None,
        description="The code itself — populated ONLY in development/test so local "
        "testing works without an SMS provider. Always null in production.",
    )


class VerifyOtpIn(BaseModel):
    phone: str = Field(..., min_length=6, max_length=24)
    code: str = Field(..., min_length=4, max_length=8, examples=["123456"])


class RefreshIn(BaseModel):
    refresh_token: str = Field(..., min_length=20, max_length=512)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(..., description="Access-token lifetime in seconds.")
    is_new_user: bool = Field(
        default=False,
        description="True when verify-otp just created the account — the client "
        "should run the profile-setup steps rather than jump straight to the app.",
    )
