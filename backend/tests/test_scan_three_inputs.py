"""Phase 3.3 verification — the three inputs from the verification prompt.

  1. a clear medication-label photo  -> reasonable text extraction
  2. a blurry / low-quality photo    -> LOW confidence, not a confident wrong
                                        answer, and no crash
  3. a non-image file renamed .jpg   -> a clear 4xx, never a 500

Run:  pytest tests/test_scan_three_inputs.py -v -s
Needs the tesseract binary (inputs 1 and 2 run real OCR).
"""

from __future__ import annotations

import io
import json
import shutil

import pytest
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import User

URL = "/api/v1/me/medications/scan"

_needs_tesseract = pytest.mark.skipif(
    shutil.which("tesseract") is None and not settings.tesseract_cmd,
    reason="tesseract binary not installed",
)


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919600000001"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _font(size: int):
    for name in ("arialbd.ttf", "Arial Bold.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def _label_image(blur: float = 0.0) -> bytes:
    img = Image.new("RGB", (760, 260), "white")
    draw = ImageDraw.Draw(img)
    draw.text((30, 45), "ATORVASTATIN", fill="black", font=_font(64))
    draw.text((30, 140), "Tablets IP  20 mg", fill="black", font=_font(38))
    if blur:
        # heavy blur + a downscale/upscale round-trip = a genuinely poor photo
        img = img.resize((190, 65)).resize((760, 260))
        img = img.filter(ImageFilter.GaussianBlur(radius=blur))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=60 if blur else 92)
    return buf.getvalue()


def _post(client, auth, filename, data, content_type):
    return client.post(URL, headers=auth, files={"file": (filename, data, content_type)})


def _show(label: str, resp) -> dict | None:
    print(f"\n----- {label} -> HTTP {resp.status_code} -----")
    try:
        body = resp.json()
    except ValueError:
        print(resp.text)
        return None
    print(json.dumps(body, indent=2, ensure_ascii=False))
    return body


@_needs_tesseract
def test_three_inputs(client, auth):
    # ---------- 1. clear label ----------
    clear = _post(client, auth, "label.jpg", _label_image(), "image/jpeg")
    clear_body = _show("1) CLEAR label photo", clear)
    assert clear.status_code == 200
    assert "ATORVASTATIN" in clear_body["raw_text"].upper()
    assert clear_body["name_candidate"] is not None
    assert "ATORVASTATIN" in clear_body["name_candidate"].upper()
    assert clear_body["dosage_candidate"] == "20 mg"
    assert 0.0 < clear_body["name_confidence"] <= 1.0
    assert clear_body["confirmation_required"] is True

    # ---------- 2. blurry / low-quality ----------
    blurry = _post(client, auth, "label.jpg", _label_image(blur=9.0), "image/jpeg")
    blurry_body = _show("2) BLURRY / low-quality photo", blurry)
    assert blurry.status_code == 200, "must degrade gracefully, not crash"
    assert 0.0 <= blurry_body["name_confidence"] <= 1.0
    # low confidence, not a confident (possibly wrong) answer
    assert blurry_body["name_confidence"] < clear_body["name_confidence"]
    assert blurry_body["name_confidence"] < 0.6
    # a null candidate is an acceptable "couldn't read it" outcome
    assert (
        blurry_body["name_candidate"] is None
        or blurry_body["name_confidence"] < 0.6
    )
    assert blurry_body["confirmation_required"] is True

    # ---------- 3. non-image renamed .jpg ----------
    not_an_image = b"From: pharmacy\nRx: take one tablet daily.\nPlain text, not an image.\n"
    renamed = _post(client, auth, "prescription.jpg", not_an_image, "image/jpeg")
    renamed_body = _show("3) NON-IMAGE renamed prescription.jpg", renamed)
    assert 400 <= renamed.status_code < 500, "must be a clear 4xx, never a 5xx"
    assert renamed.status_code == 422
    assert renamed_body["detail"]  # a human-readable reason
    assert "image" in renamed_body["detail"].lower()

    print(
        "\nSUMMARY: clear conf={:.2f}  blurry conf={:.2f}  non-image -> {}".format(
            clear_body["name_confidence"],
            blurry_body["name_confidence"],
            renamed.status_code,
        )
    )
