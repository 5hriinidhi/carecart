"""GET /foods/search — type-ahead over the everyday-food dataset.

A search-only alternative to the barcode scan: the user types a food name (a
home dish or a packaged product) and gets its facts back. Static reference data
(``food_catalog``, loaded by ``scripts.load_food_catalog``); auth-required, and
it returns nothing about the caller.
"""

from __future__ import annotations

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.api.deps import CurrentUser, DbSession
from app.models import FoodCatalog
from app.schemas.foods import FoodHit, FoodSearchOut

router = APIRouter(prefix="/foods", tags=["foods"])


def _like_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


@router.get("/search", response_model=FoodSearchOut, operation_id="foods_search")
def search_foods(
    user: CurrentUser,
    db: DbSession,
    q: str = Query(..., min_length=2, max_length=80, description="Name fragment."),
    limit: int = Query(20, ge=1, le=50),
):
    term = " ".join(q.split()).strip().lower()
    if len(term) < 2:
        return FoodSearchOut(query=q, results=[])

    esc = _like_escape(term)
    prefix = f"{esc}%"
    contains = f"%{esc}%"
    name_l = func.lower(FoodCatalog.name)
    brand_l = func.lower(func.coalesce(FoodCatalog.brand, ""))

    stmt = (
        select(FoodCatalog)
        .where(name_l.like(contains, escape="\\") | brand_l.like(contains, escape="\\"))
        .order_by(
            name_l.like(prefix, escape="\\").desc(),  # name-prefix hits first
            func.length(FoodCatalog.name),
            FoodCatalog.name,
        )
        .limit(limit)
    )

    rows = db.scalars(stmt).all()
    return FoodSearchOut(
        query=q,
        results=[FoodHit.model_validate(r) for r in rows],
    )
