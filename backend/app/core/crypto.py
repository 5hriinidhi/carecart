"""Application-layer encryption for the health vault.

Sensitive medication / condition columns are Fernet-encrypted *before* they
reach Postgres, so a database dump, a replica, or a stolen backup never exposes
plaintext — independent of any disk-level encryption Postgres may also have.

Keys come from settings (``ENCRYPTION_KEY`` + optional ``ENCRYPTION_KEYS_OLD``),
never from source. ``MultiFernet`` lets a rotated key still decrypt old rows:
the first key encrypts, every key can decrypt.
"""

from __future__ import annotations

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

from app.core.config import settings

__all__ = ["encrypt", "decrypt", "InvalidToken"]


def _fernet() -> MultiFernet:
    keys = [settings.encryption_key, *settings.encryption_keys_old_list]
    return MultiFernet([Fernet(k.encode()) for k in keys])


def encrypt(plaintext: str) -> str:
    """Plaintext -> urlsafe-base64 Fernet token (str)."""
    return _fernet().encrypt(plaintext.encode()).decode()


def decrypt(token: str) -> str:
    """Fernet token -> plaintext. Raises ``InvalidToken`` if it can't be
    decrypted with any configured key (tampering, wrong key, corruption)."""
    return _fernet().decrypt(token.encode()).decode()
