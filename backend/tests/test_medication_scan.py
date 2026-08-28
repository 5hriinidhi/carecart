"""Phase 3.3 — medication label OCR ingestion endpoint."""

from __future__ import annotations

import io
import shutil

import pytest
from PIL import Image, ImageDraw

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import User
from app.services import ocr

URL = "/api/v1/me/medications/scan"


def _png_bytes(size=(400, 120)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, "white").save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919000000099"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _fail_if_called(*_a, **_kw):  # sentinel: OCR must not run
    raise AssertionError("OCR ran before upload validation")


# ------------------------------------------------------------ pre-OCR guards --
def test_scan_requires_a_jwt(client):
    r = client.post(URL, files={"file": ("label.png", _png_bytes(), "image/png")})
    assert r.status_code == 401


def test_non_image_content_type_is_rejected_before_ocr(client, auth, monkeypatch):
    monkeypatch.setattr("app.services.ocr.extract_text", _fail_if_called)
    r = client.post(URL, headers=auth, files={"file": ("notes.txt", b"hello", "text/plain")})
    assert r.status_code == 415
    assert "label" in r.json()["detail"].lower()


def test_upload_over_10mb_is_rejected_before_ocr(client, auth, monkeypatch):
    monkeypatch.setattr("app.services.ocr.extract_text", _fail_if_called)
    oversized = b"\x89PNG\r\n\x1a\n" + b"\x00" * (11 * 1024 * 1024)
    r = client.post(URL, headers=auth, files={"file": ("big.png", oversized, "image/png")})
    assert r.status_code == 413
    assert "10 MB" in r.json()["detail"]


def test_image_content_type_but_not_a_real_image_is_422(client, auth):
    # real OCR path — open_image fails before tesseract is ever called
    files = {"file": ("fake.png", b"not a png at all", "image/png")}
    r = client.post(URL, headers=auth, files=files)
    assert r.status_code == 422


def test_empty_file_is_422(client, auth, monkeypatch):
    monkeypatch.setattr("app.services.ocr.extract_text", _fail_if_called)
    r = client.post(URL, headers=auth, files={"file": ("empty.png", b"", "image/png")})
    assert r.status_code == 422


# ------------------------------------------------- guess + no auto-save --
def test_scan_returns_a_structured_guess_and_saves_nothing(client, auth, monkeypatch):
    label = (
        "TELMISARTAN TABLETS IP\n"
        "Telma 40\n"
        "Composition: Telmisartan 40 mg\n"
        "Store below 30 C. Keep away from children."
    )
    monkeypatch.setattr("app.services.ocr.extract_text", lambda _b: (label, 0.9))

    r = client.post(URL, headers=auth, files={"file": ("label.png", _png_bytes(), "image/png")})
    assert r.status_code == 200
    body = r.json()

    assert body["confirmation_required"] is True
    assert body["name_candidate"].lower() == "telmisartan"
    assert 0.0 < body["name_confidence"] <= 1.0
    assert body["dosage_candidate"] == "40 mg"
    assert "TELMISARTAN" in body["raw_text"]

    # the scan did NOT create a medication
    assert client.get("/api/v1/me/medications", headers=auth).json() == []

    # the user confirms + saves it through the 3.2 endpoint
    saved = client.post(
        "/api/v1/me/medications",
        headers=auth,
        json={"name": body["name_candidate"], "dosage": body["dosage_candidate"]},
    )
    assert saved.status_code == 201
    assert len(client.get("/api/v1/me/medications", headers=auth).json()) == 1


def test_extracted_text_is_sanitized(client, auth, monkeypatch):
    raw = "Aspirin\x00\x07\x1b\x9d 100 mg​\r\n" + ("padding​ " * 3000)
    monkeypatch.setattr("app.services.ocr.extract_text", lambda _b: (raw, 0.8))

    body = client.post(
        URL, headers=auth, files={"file": ("label.png", _png_bytes(), "image/png")}
    ).json()

    text = body["raw_text"]
    for bad in ("\x00", "\x07", "\x1b", "\x9d", "​"):
        assert bad not in text
    assert len(text) <= settings.ocr_text_max_chars + 1  # +1 for the ellipsis
    assert body["raw_text_truncated"] is True


def test_ocr_unavailable_returns_503(client, auth, monkeypatch):
    def _boom(_b):
        raise ocr.OcrUnavailable("no tesseract")

    monkeypatch.setattr("app.services.ocr.extract_text", _boom)
    r = client.post(URL, headers=auth, files={"file": ("label.png", _png_bytes(), "image/png")})
    assert r.status_code == 503


# ------------------------------------------------------------- unit tests --
def test_sanitize_text_strips_and_caps():
    out, truncated = ocr.sanitize_text("a\x00b\tc\n\n\n\nd  e​f", max_chars=1000)
    assert "\x00" not in out and "\t" not in out and "​" not in out
    assert "\n\n\n" not in out and "  " not in out
    assert truncated is False

    capped, was_cut = ocr.sanitize_text("x" * 50, max_chars=10)
    assert was_cut is True and len(capped) == 11 and capped.endswith("…")


def test_guess_medication_picks_a_name_over_boilerplate():
    g = ocr.guess_medication("Amoxicillin 500 mg tablets store cool dry place", 0.9)
    assert g.name_candidate == "Amoxicillin"
    assert g.dosage_candidate == "500 mg"
    assert 0.0 < g.name_confidence <= 1.0

    none = ocr.guess_medication("tablets store keep away from light and moisture", 0.9)
    assert none.name_candidate is None and none.name_confidence == 0.0


# --------------------------------------------------- real end-to-end OCR --
@pytest.mark.skipif(
    shutil.which("tesseract") is None and not settings.tesseract_cmd,
    reason="tesseract binary not installed",
)
def test_real_ocr_reads_a_rendered_label(client, auth):
    img = Image.new("RGB", (640, 200), "white")
    draw = ImageDraw.Draw(img)
    from PIL import ImageFont

    try:
        font = ImageFont.truetype("arialbd.ttf", 56)
    except OSError:
        try:
            font = ImageFont.truetype("DejaVuSans-Bold.ttf", 56)
        except OSError:
            font = ImageFont.load_default(size=56)
    draw.text((24, 70), "IBUPROFEN 200 mg", fill="black", font=font)
    buf = io.BytesIO()
    img.save(buf, format="PNG")

    r = client.post(URL, headers=auth, files={"file": ("ibu.png", buf.getvalue(), "image/png")})
    assert r.status_code == 200
    body = r.json()
    assert "IBUPROFEN" in body["raw_text"].upper()
    assert body["name_candidate"] is not None
    assert "IBUPROFEN" in body["name_candidate"].upper()
    assert body["dosage_candidate"] == "200 mg"
    assert body["name_confidence"] > 0.0
    # still nothing saved
    assert client.get("/api/v1/me/medications", headers=auth).json() == []
