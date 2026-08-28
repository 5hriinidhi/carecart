"""Custom SQLAlchemy column types."""

from __future__ import annotations

import json
from typing import Any

from sqlalchemy import Text
from sqlalchemy.types import TypeDecorator

from app.core.crypto import decrypt, encrypt


class EncryptedString(TypeDecorator):
    """A string column that is Fernet-encrypted at the application layer.

    Stored as ``TEXT`` (a base64 token). Because Fernet uses a random IV, the
    ciphertext differs every write — so these columns can only ever be filtered
    by other columns (we scope every query by ``user_id``), never by their own
    value.
    """

    impl = Text
    cache_ok = True

    def process_bind_param(self, value: str | None, dialect: Any) -> str | None:
        if value is None:
            return None
        return encrypt(value)

    def process_result_value(self, value: str | None, dialect: Any) -> str | None:
        if value is None:
            return None
        return decrypt(value)


class EncryptedJSON(TypeDecorator):
    """A JSON value (dict / list) Fernet-encrypted at rest. Stored as an
    encrypted ``TEXT`` blob - never queryable by its contents, only by the
    row's other columns (we always scope by ``user_id``)."""

    impl = Text
    cache_ok = True

    def process_bind_param(self, value: Any, dialect: Any) -> str | None:
        if value is None:
            return None
        return encrypt(json.dumps(value, separators=(",", ":"), ensure_ascii=False))

    def process_result_value(self, value: str | None, dialect: Any) -> Any:
        if value is None:
            return None
        return json.loads(decrypt(value))
