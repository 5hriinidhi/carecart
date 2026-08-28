"""GET /products/{barcode} — Open Food Facts lookup with a >= 24h Postgres cache.

On a hit: a normalised product (name, ingredients, nutrition per 100 g).
On a miss: 404 with ``fallback: "ocr"`` so the client scans the ingredients list.
Both outcomes are cached, so repeat scans of the same barcode don't touch OFF.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import JSONResponse
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.api.deps import CurrentUser, DbSession
from app.core.config import settings
from app.models import Product
from app.schemas.product import ProductNotFoundOut, ProductOut
from app.services import openfoodfacts

router = APIRouter(prefix="/products", tags=["products"])


def _now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _aware(d: dt.datetime) -> dt.datetime:
    return d if d.tzinfo else d.replace(tzinfo=dt.UTC)


def _not_found_response(barcode: str) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_404_NOT_FOUND,
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
def get_product(barcode: str, user: CurrentUser, db: DbSession):
    barcode = barcode.strip()
    if not (barcode.isdigit() and 8 <= len(barcode) <= 14):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "Barcode must be 8–14 digits."
        )

    ttl = dt.timedelta(hours=settings.product_cache_ttl_hours)
    row = db.get(Product, barcode)
    fresh = row is not None and _aware(row.refreshed_at) > _now() - ttl

    if fresh:
        if row.off_status == "not_found":
            return _not_found_response(barcode)
        return _to_out(row, cached=True)

    # cache miss or stale -> ask Open Food Facts
    try:
        off_product = openfoodfacts.fetch_product(barcode)
    except openfoodfacts.OpenFoodFactsError:
        if row is not None and row.off_status == "found":
            return _to_out(row, cached=True, stale=True)  # expired data beats nothing
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Couldn't reach the product database. Try again, or scan the ingredients list.",
        ) from None

    now = _now()
    if off_product is None:
        _upsert(db, {"barcode": barcode, "off_status": "not_found", "refreshed_at": now})
        db.commit()
        return _not_found_response(barcode)

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
    return _to_out(row, cached=False)
