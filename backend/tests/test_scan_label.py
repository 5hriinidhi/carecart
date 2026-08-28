"""Phase 4.2 - POST /products/scan-label: OCR an ingredients list -> draft list + raw text."""

from __future__ import annotations

import io
import shutil

import pytest
from PIL import Image, ImageDraw, ImageFont
from sqlalchemy import text

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import User
from app.services import ocr
from app.services.ocr import parse_ingredients

URL = "/api/v1/products/scan-label"

_needs_tesseract = pytest.mark.skipif(
    shutil.which("tesseract") is None and not settings.tesseract_cmd,
    reason="tesseract binary not installed",
)


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919222900001"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _png(size=(700, 260)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, "white").save(buf, format="PNG")
    return buf.getvalue()


def _label_png(lines: list[str]) -> bytes:
    img = Image.new("RGB", (900, 90 + 60 * len(lines)), "white")
    draw = ImageDraw.Draw(img)
    for name in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            font = ImageFont.truetype(name, 34)
            break
        except OSError:
            font = ImageFont.load_default(size=34)
    for i, line in enumerate(lines):
        draw.text((25, 25 + 60 * i), line, fill="black", font=font)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _fail_if_called(*_a, **_kw):
    raise AssertionError("OCR ran before upload validation")


# ------------------------------------------------------ pre-OCR guards --
def test_requires_a_jwt(client):
    r = client.post(URL, files={"file": ("l.png", _png(), "image/png")})
    assert r.status_code == 401


def test_non_image_is_rejected_before_ocr(client, auth, monkeypatch):
    monkeypatch.setattr("app.services.ocr.extract_text", _fail_if_called)
    r = client.post(URL, headers=auth, files={"file": ("notes.txt", b"hi", "text/plain")})
    assert r.status_code == 415


def test_oversize_is_rejected_before_ocr(client, auth, monkeypatch):
    monkeypatch.setattr("app.services.ocr.extract_text", _fail_if_called)
    big = b"\x89PNG\r\n\x1a\n" + b"\x00" * (11 * 1024 * 1024)
    r = client.post(URL, headers=auth, files={"file": ("big.png", big, "image/png")})
    assert r.status_code == 413


def test_not_a_real_image_is_422(client, auth):
    r = client.post(URL, headers=auth, files={"file": ("x.png", b"nope", "image/png")})
    assert r.status_code == 422


def test_ocr_unavailable_is_503(client, auth, monkeypatch):
    def _boom(_b):
        raise ocr.OcrUnavailable("no tesseract")

    monkeypatch.setattr("app.services.ocr.extract_text", _boom)
    r = client.post(URL, headers=auth, files={"file": ("l.png", _png(), "image/png")})
    assert r.status_code == 503


# --------------------------------------------- parse + editable contract --
def test_returns_parsed_list_and_editable_raw_text(client, auth, monkeypatch):
    monkeypatch.setattr(
        "app.services.ocr.extract_text",
        lambda _b: ("Ingredients: water, sugar, iodised salt; yeast", 0.9),
    )
    r = client.post(URL, headers=auth, files={"file": ("l.png", _png(), "image/png")})
    assert r.status_code == 200
    body = r.json()
    assert body["ingredients"] == ["water", "sugar", "iodised salt", "yeast"]
    assert body["raw_text"] == "Ingredients: water, sugar, iodised salt; yeast"
    assert body["editable"] is True  # never ground truth
    assert body["source"] == "ocr"
    assert body["raw_text_truncated"] is False


def test_scan_label_saves_nothing(client, db, auth, monkeypatch):
    monkeypatch.setattr("app.services.ocr.extract_text", lambda _b: ("a, b, c", 0.5))
    client.post(URL, headers=auth, files={"file": ("l.png", _png(), "image/png")})
    assert db.execute(text("SELECT count(*) FROM products")).scalar_one() == 0


@_needs_tesseract
def test_real_ocr_parses_a_rendered_ingredients_list(client, auth):
    png = _label_png(
        [
            "INGREDIENTS: Sugar, Palm Oil,",
            "Wheat Flour, Cocoa Powder,",
            "Milk Solids, Soy Lecithin, Salt",
        ]
    )
    r = client.post(URL, headers=auth, files={"file": ("label.png", png, "image/png")})
    assert r.status_code == 200
    body = r.json()
    joined = " | ".join(body["ingredients"]).lower()
    for expected in ("sugar", "palm oil", "wheat flour", "cocoa", "salt"):
        assert expected in joined, f"missing {expected!r} in {body['ingredients']}"
    assert "INGREDIENTS" in body["raw_text"].upper()
    assert body["editable"] is True


# ------------------------------------------------- parse_ingredients unit --
def test_parse_splits_on_commas_and_semicolons():
    assert parse_ingredients("water, sugar; salt , yeast") == [
        "water", "sugar", "salt", "yeast"
    ]


def test_parse_strips_the_label_prefix():
    assert parse_ingredients("INGREDIENTS: milk, cream")[0] == "milk"
    assert parse_ingredients("Ingrédients : lait, crème") == ["lait", "crème"]
    assert parse_ingredients("Contains: wheat, barley") == ["wheat", "barley"]


def test_parse_keeps_parenthetical_sub_lists_whole():
    got = parse_ingredients("colour (caramel, E150d), acidity regulator (E330)")
    assert got == ["colour (caramel, E150d)", "acidity regulator (E330)"]


def test_parse_strips_bullets_and_edge_punctuation():
    assert parse_ingredients("• Sugar . ; - Palm oil * , (Cocoa)") == [
        "Sugar", "Palm oil", "Cocoa"
    ]


def test_parse_keeps_percentages():
    assert parse_ingredients("hazelnuts 13%, skimmed milk powder 6.6%") == [
        "hazelnuts 13%",
        "skimmed milk powder 6.6%",
    ]


def test_parse_drops_boilerplate_and_junk():
    text = (
        "sugar, cocoa, May contain traces of nuts, www.brand.com, "
        "Best before end: see base, -, 123"
    )
    assert parse_ingredients(text) == ["sugar", "cocoa"]


def test_parse_dedupes_case_insensitively():
    assert parse_ingredients("sugar, Sugar, SUGAR, salt") == ["sugar", "salt"]


def test_parse_one_per_line_fallback_when_no_delimiters():
    assert parse_ingredients("Water\nSugar\nSalt\nYeast") == [
        "Water", "Sugar", "Salt", "Yeast"
    ]


def test_parse_multiword_ingredient_broken_across_lines_stays_whole():
    assert parse_ingredients("skimmed milk\npowder, cocoa mass, sugar") == [
        "skimmed milk powder",
        "cocoa mass",
        "sugar",
    ]


def test_parse_empty_or_noise_only_text():
    assert parse_ingredients("") == []
    assert parse_ingredients("   \n . ; - \n ") == []
