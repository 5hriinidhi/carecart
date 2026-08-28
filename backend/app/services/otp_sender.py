"""OTP delivery.

Two implementations:
  * ``ConsoleOtpSender`` — dev fallback when no provider is configured. It logs
    that a code was issued (masked phone only) and NOTHING else. The code is
    surfaced to the developer via the ``dev_code`` field of the request-otp
    response, not through a log.
  * ``HttpOtpSender`` — a generic HTTPS sender. Adapt the payload to your
    provider (Twilio / MSG91 / …); auth is ``Bearer OTP_PROVIDER_API_KEY``
    against ``OTP_PROVIDER_URL``. On failure it logs the exception *class* and
    the masked phone — never the response body (which could echo the code).
"""

from __future__ import annotations

import logging
from typing import Protocol

import httpx

from app.core.config import settings
from app.core.security import mask_phone

logger = logging.getLogger("carecart.otp")


class OtpDeliveryError(RuntimeError):
    """The code could not be handed to the delivery channel."""


_FAILED_STATUS = {"failed", "error", "rejected", "undelivered", "false", "0"}


def _looks_delivered(resp: httpx.Response) -> bool:
    """Best-effort read of a 2xx provider response. Unknown shapes -> assume OK."""
    try:
        payload = resp.json()
    except (ValueError, UnicodeDecodeError):
        return True
    if not isinstance(payload, dict):
        return True
    if payload.get("error") or payload.get("errors"):
        return False
    status_val = str(payload.get("status", payload.get("Status", ""))).strip().lower()
    return status_val not in _FAILED_STATUS


class OtpSender(Protocol):
    def send(self, phone_e164: str, code: str) -> None: ...


class ConsoleOtpSender:
    def send(self, phone_e164: str, code: str) -> None:  # noqa: ARG002 - code intentionally unused
        logger.info(
            "OTP issued for %s (console sender: no SMS sent, code withheld from logs)",
            mask_phone(phone_e164),
        )


class HttpOtpSender:
    def __init__(self, url: str, api_key: str, sender_id: str) -> None:
        self._url = url
        self._api_key = api_key
        self._sender_id = sender_id

    def send(self, phone_e164: str, code: str) -> None:
        message = (
            f"{code} is your CareCart verification code. "
            f"It expires in {settings.otp_ttl_minutes} minutes."
        )
        try:
            resp = httpx.post(
                self._url,
                headers={"Authorization": f"Bearer {self._api_key}"},
                json={"to": phone_e164, "sender": self._sender_id, "message": message},
                timeout=10.0,
            )
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            # covers connect / read / timeout / non-2xx. Deliberately no response
            # body, no message, no code in this log line.
            logger.error(
                "OTP delivery failed for %s: %s", mask_phone(phone_e164), exc.__class__.__name__
            )
            raise OtpDeliveryError("could not send verification code") from exc

        # Some providers answer 200 with a failure in the body. Treat a top-level
        # `error` / `errors` key, or a `status` that reads as failed, as a failure
        # rather than silently returning "sent". (Provider adapters can refine.)
        if not _looks_delivered(resp):
            logger.error("OTP provider reported a non-delivery for %s", mask_phone(phone_e164))
            raise OtpDeliveryError("provider did not accept the message")

        logger.info("OTP delivered to %s via provider", mask_phone(phone_e164))


def get_otp_sender() -> OtpSender:
    if settings.otp_provider_url and settings.otp_provider_api_key:
        return HttpOtpSender(
            settings.otp_provider_url, settings.otp_provider_api_key, settings.otp_sender_id
        )
    if settings.is_production:
        raise OtpDeliveryError("OTP provider is not configured (set OTP_PROVIDER_URL + key)")
    logger.warning("OTP provider not configured — using the dev console sender")
    return ConsoleOtpSender()
