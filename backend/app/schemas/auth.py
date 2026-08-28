"""Auth API payloads for the onboarding login -> otp flow."""

from __future__ import annotations

from pydantic import BaseModel, Field


class RequestOtpIn(BaseModel):
    phone: str = Field(
        ...,
        min_length=6,
        max_length=24,
        examples=["+919876543210", "9876543210"],
        description="Phone number in E.164, or a national number for the default country code.",
    )


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
