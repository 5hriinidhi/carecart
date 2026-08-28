"""Medication-label OCR: decode an image, extract text with Tesseract, and make
a *guess* at the drug name for the user to confirm.

Nothing here writes to the database. The endpoint returns a candidate; the user
confirms and saves it through the 3.2 ``POST /me/medications`` endpoint. This is
consistent with "no live LLM at runtime" - the guess is a deterministic
heuristic over the OCR output, not a model call.
"""

from __future__ import annotations

import io
import re
import unicodedata
from dataclasses import dataclass

import pytesseract
from PIL import Image, UnidentifiedImageError

from app.core.config import settings

if settings.tesseract_cmd:
    pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd

# guard against decompression-bomb images
Image.MAX_IMAGE_PIXELS = 40_000_000


class InvalidImage(ValueError):
    """The uploaded bytes are not a readable image."""


class OcrUnavailable(RuntimeError):
    """The Tesseract binary is missing or unusable."""


@dataclass(frozen=True)
class MedicationGuess:
    name_candidate: str | None
    name_confidence: float  # 0.0 - 1.0
    dosage_candidate: str | None


# --------------------------------------------------------------------- decode --
def open_image(image_bytes: bytes) -> Image.Image:
    try:
        probe = Image.open(io.BytesIO(image_bytes))
        probe.verify()  # structural check without a full decode
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise InvalidImage("not a readable image") from exc
    # verify() leaves the image object unusable - reopen for real work
    return Image.open(io.BytesIO(image_bytes))


# ------------------------------------------------------------------------ OCR --
def extract_text(image_bytes: bytes) -> tuple[str, float]:
    """Return (raw text, mean word confidence 0-1). Raises :class:`InvalidImage`
    or :class:`OcrUnavailable` - Tesseract is never invoked for a bad image."""
    img = open_image(image_bytes)
    try:
        data = pytesseract.image_to_data(img, output_type=pytesseract.Output.DICT)
    except pytesseract.TesseractNotFoundError as exc:
        raise OcrUnavailable("tesseract binary not found") from exc

    lines: dict[tuple[int, int, int], list[str]] = {}
    confs: list[int] = []
    for i, token in enumerate(data["text"]):
        if not token.strip():
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines.setdefault(key, []).append(token)
        try:
            c = int(float(data["conf"][i]))
        except (TypeError, ValueError):
            c = -1
        if c >= 0:
            confs.append(c)

    text = "\n".join(" ".join(toks) for _, toks in sorted(lines.items()))
    mean_conf = round(sum(confs) / len(confs) / 100.0, 3) if confs else 0.0
    return text, mean_conf


# ------------------------------------------------------------------- sanitise --
_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")
_INLINE_WS_RE = re.compile(r"[^\S\n]+")  # whitespace runs except newline
_BLANK_LINES_RE = re.compile(r"\n{3,}")


def sanitize_text(raw: str, *, max_chars: int) -> tuple[str, bool]:
    """Strip control/format characters, collapse whitespace, cap length.
    Returns (clean text, was_truncated)."""
    cleaned = _CONTROL_RE.sub("", raw.replace("\t", " "))
    # drop any remaining Unicode control/format code points (keep newlines)
    cleaned = "".join(
        ch for ch in cleaned if ch == "\n" or not unicodedata.category(ch).startswith("C")
    )
    cleaned = _INLINE_WS_RE.sub(" ", cleaned)
    cleaned = _BLANK_LINES_RE.sub("\n\n", cleaned)
    cleaned = "\n".join(line.strip() for line in cleaned.split("\n")).strip()

    truncated = len(cleaned) > max_chars
    if truncated:
        cleaned = cleaned[:max_chars].rstrip() + "…"
    return cleaned, truncated


# --------------------------------------------------------- ingredient parsing --
# a leading "Ingredients:" / "Ingrédients :" / "Contains:" / "Composition -" label
_LABEL_PREFIX_RE = re.compile(
    r"^\s*(ingredient(?:e|s|es)?|ingr[ée]dients?|contains|composition)\s*[:.–—\-]*\s*",
    re.IGNORECASE,
)
_EDGE_NOISE_RE = re.compile(r"^[\s.,;:\-–—*•·°'\"()\[\]]+|"
                            r"[\s.,;:\-–—*•·°'\"]+$")
_MULTISPACE_RE = re.compile(r"\s+")
# trailing packaging text that OCR sweeps into the list
_NOT_AN_INGREDIENT_RE = re.compile(
    r"^(may contain|produced in|manufactured|packed|made in|for allergens|"
    r"allergy advice|allergen|see |best before|use by|store |keep |contains \d|"
    r"nutrition|serving|net (weight|wt)|energy|per 100|www\.|https?://|tel[:.]|email)",
    re.IGNORECASE,
)


def _split_top_level(text: str, separators: str) -> list[str]:
    """Split on `separators` that are NOT inside brackets -
    so "colour (caramel, E150d)" stays one item."""
    out: list[str] = []
    buf: list[str] = []
    depth = 0
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}" and depth > 0:
            depth -= 1
        if ch in separators and depth == 0:
            out.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    out.append("".join(buf))
    return out


def parse_ingredients(sanitized_text: str) -> list[str]:
    """OCR text of an ingredients list -> a cleaned list of individual strings.

    Splits on top-level commas / semicolons, strips OCR edge noise, drops
    fragments with no letters and obvious packaging boilerplate, de-dupes.
    This is a DRAFT for the user to correct - never treat it as ground truth.
    """
    body = _LABEL_PREFIX_RE.sub("", sanitized_text.strip(), count=1)
    flat = _MULTISPACE_RE.sub(" ", body.replace("\n", " ")).strip()

    parts = _split_top_level(flat, ",;")
    # one-per-line list with no delimiters -> fall back to line splitting
    if len([p for p in parts if p.strip()]) <= 1 and sanitized_text.count("\n") >= 2:
        parts = [
            piece
            for line in sanitized_text.split("\n")
            for piece in _split_top_level(line, ",;")
        ]

    seen: set[str] = set()
    cleaned: list[str] = []
    for part in parts:
        item = _MULTISPACE_RE.sub(" ", part).strip()
        item = _EDGE_NOISE_RE.sub("", _EDGE_NOISE_RE.sub("", item)).strip()
        # drop unbalanced brackets left by splitting (e.g. "(Cocoa)" -> "Cocoa)")
        while item.endswith(")") and item.count(")") > item.count("("):
            item = item[:-1].strip()
        while item.startswith("(") and item.count("(") > item.count(")"):
            item = item[1:].strip()
        if len(item) < 2 or not any(c.isalpha() for c in item):
            continue
        if _NOT_AN_INGREDIENT_RE.match(item):
            continue
        key = item.lower()
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(item)
        if len(cleaned) >= 200:  # a sane cap
            break
    return cleaned


# ---------------------------------------------------------------------- guess --
_STOPWORDS = frozenset(
    """tablet tablets tab tabs capsule capsules cap caps film coated oral use uses only
    store keep away from light moisture children reach dose dosage doses each contains
    active inactive ingredient ingredients excipients colour color composition therapeutic
    manufactured marketed mfd mfg exp expiry expires date price mrp inclusive taxes net
    weight quantity prescription schedule warning warnings caution read leaflet insert
    before after take taken taking doctor physician pharmacist consult not for the and with
    per twice thrice daily once bedtime morning evening night water food india limited ltd
    company batch lot""".split()
)
_DOSE_RE = re.compile(r"\b(\d+(?:\.\d+)?)\s?(mg|mcg|ug|g|ml|iu|%)\b", re.IGNORECASE)
_WORD_RE = re.compile(r"[A-Za-z][A-Za-z'\-]{3,29}")
# words that say "this really is a medicine label"
_MED_CONTEXT_RE = re.compile(
    r"\b(tablet|tablets|capsule|capsules|mg|mcg|ml|syrup|injection|ointment|cream|"
    r"dose|dosage|rx|prescription|composition|ip\b|usp|bp)\b",
    re.IGNORECASE,
)


def guess_medication(sanitized_text: str, mean_conf: float) -> MedicationGuess:
    dosage = None
    if m := _DOSE_RE.search(sanitized_text):
        unit = m.group(2).lower().replace("ug", "mcg")
        dosage = f"{m.group(1)} {unit}"

    best_word: str | None = None
    best_score = 0.0
    for raw_word in _WORD_RE.findall(sanitized_text):
        word = raw_word.strip("-'")
        if len(word) < 4 or word.lower() in _STOPWORDS:
            continue
        if sum(ch.isalpha() for ch in word) / len(word) < 0.9:
            continue
        score = float(min(len(word), 16))
        if word[:1].isupper() and not word.isupper():
            score += 6  # Title case reads like a name
        elif word.isupper() and len(word) >= 5:
            score += 3  # ALLCAPS brand
        if score > best_score:
            best_word, best_score = word, score

    if best_word is None:
        return MedicationGuess(None, 0.0, dosage)

    plausibility = min(1.0, 0.4 + best_score / 40.0)  # 0.4 - 1.0
    confidence = (mean_conf or 0.5) * plausibility
    # If nothing on the image looks like a medicine label (no dosage, no
    # "tablet"/"mg"/... context), this is probably not a medication at all -
    # halve the confidence so a non-label photo can't yield a confident guess.
    if dosage is None and not _MED_CONTEXT_RE.search(sanitized_text):
        confidence *= 0.5
    return MedicationGuess(best_word, round(confidence, 2), dosage)
