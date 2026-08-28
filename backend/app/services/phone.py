"""Phone-number normalisation to E.164.

Keeps `9876543210`, `+91 98765 43210` and `09876543210` from becoming three
different rate-limit buckets / three different users.
"""

from __future__ import annotations

import re

from app.core.config import settings

_NON_DIGITS = re.compile(r"\D+")
_E164 = re.compile(r"^\+[1-9]\d{7,14}$")


class InvalidPhoneNumber(ValueError):
    """Raised when a number can't be coerced into valid E.164."""


def normalize_e164(raw: str) -> str:
    s = (raw or "").strip()
    if s.startswith("+"):
        s = "+" + _NON_DIGITS.sub("", s)
    else:
        digits = _NON_DIGITS.sub("", s).lstrip("0")  # drop a national trunk 0
        s = f"{settings.otp_default_country_code}{digits}"

    if not _E164.match(s):
        raise InvalidPhoneNumber("phone must be a valid E.164 number")
    return s
