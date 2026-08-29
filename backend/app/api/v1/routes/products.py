"""GET /products/{barcode} — Open Food Facts lookup with a >= 24h Postgres cache.

On a hit: a normalised product (name, ingredients, nutrition per 100 g).
On a miss: 404 with ``fallback: "ocr"`` so the client scans the ingredients list.
Both outcomes are cached, so repeat scans of the same barcode don't touch OFF.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, File, HTTPException, Response, UploadFile, status
from fastapi.responses import JSONResponse
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.api.deps import CurrentUser, DbSession
from app.api.uploads import read_image_upload
from app.core.config import settings
from app.models import Product
from app.schemas.product import (
    IngredientRiskOut,
    LabelScanOut,
    ProductNotFoundOut,
    ProductOut,
    ProductRiskTagOut,
    ResolveRisksIn,
    RiskResolutionOut,
)
from app.services import ingredient_risk, ocr, openfoodfacts

router = APIRouter(prefix="/products", tags=["products"])


def _now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _aware(d: dt.datetime) -> dt.datetime:
    return d if d.tzinfo else d.replace(tzinfo=dt.UTC)


def _not_found_response(barcode: str, *, cache: str) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_404_NOT_FOUND,
        headers={"X-Cache": cache},
        content=ProductNotFoundOut(
            detail="This product isn't in the database yet. Scan its ingredients list instead.",
            barcode=barcode,
            fallback="ocr",
        ).model_dump(),
    )


def _to_out(row: Product, *, cached: bool, stale: bool = False) -> ProductOut:
    return ProductOut(
        barcode=row.barcode,
        name=row.name,
        brand=row.brand,
        ingredients=list(row.ingredients or []),
        ingredients_text=row.ingredients_text,
        nutriments=dict(row.nutriments or {}),
        serving_size=row.serving_size,
        image_url=row.image_url,
        source=row.source,
        refreshed_at=_aware(row.refreshed_at),
        cached=cached,
        stale=stale,
    )


def _upsert(db, values: dict) -> Product:
    stmt = (
        pg_insert(Product)
        .values(**values)
        .on_conflict_do_update(index_elements=["barcode"], set_=values)
    )
    db.execute(stmt)
    # the Core upsert doesn't touch the ORM identity map - drop any stale copy
    # so the reload below returns what we just wrote.
    db.expire_all()
    return db.get(Product, values["barcode"])


@router.get(
    "/{barcode}",
    response_model=ProductOut,
    responses={404: {"model": ProductNotFoundOut}},
    operation_id="products_lookup_barcode",
)
def get_product(barcode: str, user: CurrentUser, db: DbSession, response: Response):
    barcode = barcode.strip()
    if not (barcode.isdigit() and 8 <= len(barcode) <= 14):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Barcode must be 8–14 digits."
        )

    ttl = dt.timedelta(hours=settings.product_cache_ttl_hours)
    row = db.get(Product, barcode)
    fresh = row is not None and _aware(row.refreshed_at) > _now() - ttl

    if fresh:
        # served entirely from Postgres - no Open Food Facts call
        if row.off_status == "not_found":
            return _not_found_response(barcode, cache="HIT")
        response.headers["X-Cache"] = "HIT"
        return _to_out(row, cached=True)

    # cache miss or stale -> ask Open Food Facts
    try:
        off_product = openfoodfacts.fetch_product(barcode)
    except openfoodfacts.OpenFoodFactsError:
        if row is not None and row.off_status == "found":
            response.headers["X-Cache"] = "STALE"
            return _to_out(row, cached=True, stale=True)  # expired data beats nothing
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Couldn't reach the product database. Try again, or scan the ingredients list.",
        ) from None

    now = _now()
    if off_product is None:
        _upsert(db, {"barcode": barcode, "off_status": "not_found", "refreshed_at": now})
        db.commit()
        return _not_found_response(barcode, cache="MISS")

    norm = openfoodfacts.normalize(barcode, off_product)
    row = _upsert(
        db,
        {
            "barcode": barcode,
            "off_status": "found",
            "name": norm.name,
            "brand": norm.brand,
            "ingredients_text": norm.ingredients_text,
            "ingredients": norm.ingredients,
            "nutriments": norm.nutriments,
            "serving_size": norm.serving_size,
            "image_url": norm.image_url,
            "source": "openfoodfacts",
            "raw": off_product,
            "refreshed_at": now,
        },
    )
    db.commit()
    response.headers["X-Cache"] = "MISS"
    return _to_out(row, cached=False)


@router.post("/scan-label", response_model=LabelScanOut, operation_id="products_scan_label")
async def scan_ingredient_label(user: CurrentUser, file: UploadFile = File(...)):
    """OCR a photo of an ingredients list (for unbranded / regional products not
    in Open Food Facts) and parse it into individual ingredient strings.

    Returns the parsed list **and** the raw OCR text — the client must let the
    user correct obvious OCR errors before this is used. Nothing is persisted.
    """
    image_bytes = await read_image_upload(file)  # 415 / 413 / 422 before OCR

    try:
        raw_text, mean_conf = ocr.extract_text(image_bytes)
    except ocr.InvalidImage:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "That file isn't a readable image."
        ) from None
    except ocr.OcrUnavailable:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Label scanning is temporarily unavailable."
        ) from None

    text, truncated = ocr.sanitize_text(raw_text, max_chars=settings.ocr_text_max_chars)
    ingredients = ocr.parse_ingredients(text)
    confidence = round(mean_conf, 2)

    # An ingredients list basically always has more than a few words - if OCR
    # returned almost nothing, a high per-word confidence is misleading (it read
    # one word well and missed the rest, e.g. a rotated / dark photo).
    barely_any_text = len(text) < 25 or len(text.split()) < 4

    if not ingredients:
        low_confidence, note = True, (
            "Couldn't pick out any ingredients from that photo. Retake it straight-on "
            "in good light, or type the list in."
        )
    elif confidence < settings.ocr_low_confidence_threshold or barely_any_text:
        low_confidence, note = True, (
            "This photo was hard to read - some of the label may be missing or wrong. "
            "Check every line against the pack before continuing, or retake it."
        )
    else:
        low_confidence, note = False, None

    return LabelScanOut(
        ingredients=ingredients,
        raw_text=text,
        raw_text_truncated=truncated,
        ocr_confidence=confidence,
        low_confidence=low_confidence,
        note=note,
        editable=True,
    )


@router.post(
    "/resolve-risks",
    response_model=RiskResolutionOut,
    operation_id="products_resolve_risks",
)
def resolve_risks(body: ResolveRisksIn, user: CurrentUser, db: DbSession):
    """Resolve a raw ingredient list (from a 4.1 lookup or a 4.2 label scan) to
    its ``risk_compound`` tags, entirely from the pre-built static tables in
    Postgres — **no LLM / network call**.

    Ingredients that match nothing come back with ``method="unverified"`` (and a
    ``caution_factors`` line), never silently dropped or treated as safe, and are
    written to the ``unresolved_ingredients`` queue for the offline batch job.
    """
    sample = body.barcode or body.product_name
    result = ingredient_risk.resolve_ingredients(
        db,
        body.ingredients,
        nutriments=body.nutriments,
        sample_product=sample,
        queue_unresolved=settings.risk_queue_unresolved,
    )
    db.commit()  # persist any unresolved-queue upserts

    return RiskResolutionOut(
        ingredients=[
            IngredientRiskOut(
                input_text=i.input_text,
                clean_text=i.clean_text,
                risk_compounds=i.risk_compounds,
                method=i.method,
                confidence=i.confidence,
            )
            for i in result.ingredients
        ],
        product_tags=[
            ProductRiskTagOut(
                risk_compound=t.risk_compound,
                nutrient_key=t.nutrient_key,
                value=t.value,
                threshold=t.threshold,
                confidence=t.confidence,
                method=t.method,
                rationale=t.rationale,
            )
            for t in result.product_tags
        ],
        risk_compounds=result.risk_compounds,
        unverified=result.unverified,
        unverified_count=result.unverified_count,
        caution_factors=result.caution_factors,
        resolved_count=result.resolved_count,
        benign_count=result.benign_count,
    )
