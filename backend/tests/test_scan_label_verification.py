"""Phase 4.2 verification - POST /products/scan-label on a clear label vs a
rotated + dim one. Both must return something usable, and a bad photo must be
flagged (low_confidence + note), never an empty/garbled result with no
explanation.

Run:  pytest tests/test_scan_label_verification.py -v -s   (needs tesseract)
"""

from __future__ import annotations

import io
import json
import shutil

import pytest
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import User

URL = "/api/v1/products/scan-label"

pytestmark = pytest.mark.skipif(
    shutil.which("tesseract") is None and not settings.tesseract_cmd,
    reason="tesseract binary not installed",
)

_LINES = [
    "INGREDIENTS: Whole wheat flour, water,",
    "sugar, sunflower oil, iodised salt, yeast,",
    "emulsifier (soya lecithin), acidity",
    "regulator (calcium propionate).",
]


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919222950001"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _font(size: int):
    for name in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def _render_label() -> Image.Image:
    img = Image.new("RGB", (1000, 90 + 66 * len(_LINES)), "white")
    draw = ImageDraw.Draw(img)
    for i, line in enumerate(_LINES):
        draw.text((28, 24 + 66 * i), line, fill="black", font=_font(34))
    return img


def _png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.convert("RGB").save(buf, format="PNG")
    return buf.getvalue()


def _post(client, auth, img: Image.Image) -> dict:
    r = client.post(URL, headers=auth, files={"file": ("label.png", _png(img), "image/png")})
    assert r.status_code == 200, r.text
    return r.json()


def _report(tag: str, body: dict) -> None:
    print(f"\n===== {tag} =====")
    print(f"ocr_confidence : {body['ocr_confidence']}")
    print(f"low_confidence : {body['low_confidence']}")
    print(f"note           : {body['note']}")
    print("raw_text:")
    for line in body["raw_text"].splitlines():
        print(f"  | {line}")
    print(f"parsed list ({len(body['ingredients'])}):")
    for item in body["ingredients"]:
        print(f"  - {item}")


def _assert_never_silently_bad(body: dict) -> None:
    """The core contract: never an empty / garbled result with no explanation."""
    assert body["editable"] is True
    assert 0.0 <= body["ocr_confidence"] <= 1.0
    if not body["ingredients"]:
        assert body["low_confidence"] is True and body["note"], (
            "an empty parse must carry low_confidence + a note explaining why"
        )
    elif body["ocr_confidence"] < settings.ocr_low_confidence_threshold:
        assert body["low_confidence"] is True and body["note"], (
            "a low-confidence parse must be flagged with a note"
        )


def test_clear_vs_degraded_label(client, auth):
    # ---------- case 1: clean, straight, well-lit ----------
    clear = _post(client, auth, _render_label())
    _report("CASE 1 - clear label", clear)

    joined = " | ".join(clear["ingredients"]).lower()
    for expected in ("whole wheat flour", "water", "sugar", "sunflower oil", "salt", "yeast"):
        assert expected in joined, f"clear scan missing {expected!r}: {clear['ingredients']}"
    assert clear["ocr_confidence"] >= 0.5
    assert clear["low_confidence"] is False and clear["note"] is None
    # parenthetical sub-lists stay intact, not shredded on the inner comma
    assert any("(" in x and ")" in x for x in clear["ingredients"])
    _assert_never_silently_bad(clear)

    # ---------- case 2: mildly rotated + a bit dark + soft focus ----------
    mild = _render_label().rotate(-6, expand=True, fillcolor="white")
    mild = ImageEnhance.Brightness(mild).enhance(0.6)
    mild = mild.filter(ImageFilter.GaussianBlur(radius=0.7))
    case2 = _post(client, auth, mild)
    _report("CASE 2 - rotated ~6deg + dim + soft focus", case2)
    assert case2["ocr_confidence"] <= clear["ocr_confidence"]  # degrades, not silently
    _assert_never_silently_bad(case2)

    # ---------- case 3: badly rotated + very dark + blurred ----------
    bad = _render_label().rotate(-14, expand=True, fillcolor="white")
    bad = ImageEnhance.Brightness(bad).enhance(0.4)
    bad = bad.filter(ImageFilter.GaussianBlur(radius=1.4))
    case3 = _post(client, auth, bad)
    _report("CASE 3 - badly rotated + very dark + blurred", case3)
    assert case3["ocr_confidence"] < clear["ocr_confidence"]
    _assert_never_silently_bad(case3)
    # a photo this bad should end up flagged one way or the other
    assert case3["low_confidence"] is True and case3["note"]

    print("\n----- summary -----")
    for tag, b in (("clear", clear), ("mild", case2), ("bad", case3)):
        print(json.dumps({"case": tag, "ocr_confidence": b["ocr_confidence"],
                          "low_confidence": b["low_confidence"],
                          "n_ingredients": len(b["ingredients"]),
                          "note": b["note"]}))
