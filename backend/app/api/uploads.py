"""Shared guard for multipart image uploads (medication + ingredient label scans).

Enforces the content-type allow-list and the size cap BEFORE the bytes reach an
OCR / decode step, reading the body in chunks so an oversized upload is rejected
without being buffered in full.
"""

from __future__ import annotations

from fastapi import HTTPException, UploadFile, status

from app.core.config import settings

ALLOWED_IMAGE_TYPES = frozenset(
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
        "image/tiff",
        "image/bmp",
        "image/heic",
        "image/heif",
    }
)


async def read_image_upload(file: UploadFile) -> bytes:
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    if not content_type.startswith("image/") or content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            f"Upload a photo of the label (got content type '{content_type or 'unknown'}').",
        )

    cap = settings.ocr_max_upload_bytes
    limit_mb = cap // (1024 * 1024)
    if file.size is not None and file.size > cap:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE, f"Image is larger than {limit_mb} MB."
        )

    buf = bytearray()
    while chunk := await file.read(64 * 1024):
        buf.extend(chunk)
        if len(buf) > cap:
            raise HTTPException(
                status.HTTP_413_CONTENT_TOO_LARGE, f"Image is larger than {limit_mb} MB."
            )
    if not buf:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "The uploaded file is empty.")
    return bytes(buf)
