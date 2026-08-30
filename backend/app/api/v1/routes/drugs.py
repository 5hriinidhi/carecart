"""GET /drugs/search — type-ahead over the medicine catalogue (Step 3).

Lets the app offer a searchable picker for "add a medication" instead of a
free-text field or an OCR strip-reader. Static reference data (``drug_catalog``,
loaded by ``scripts.load_drug_catalog``); auth-required like everything else, and
it returns nothing about the caller — just brand-name matches.
"""

from __future__ import annotations

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.api.deps import CurrentUser, DbSession
from app.models import DrugCatalog
from app.schemas.drugs import DrugHit, DrugSearchOut

router = APIRouter(prefix="/drugs", tags=["drugs"])


def _like_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


@router.get("/search", response_model=DrugSearchOut, operation_id="drugs_search")
def search_drugs(
    user: CurrentUser,
    db: DbSession,
    q: str = Query(..., min_length=2, max_length=80, description="Name fragment."),
    limit: int = Query(20, ge=1, le=50),
):
    term = " ".join(q.split()).strip().lower()
    if len(term) < 2:
        return DrugSearchOut(query=q, results=[])

    esc = _like_escape(term)
    prefix = f"{esc}%"
    contains = f"%{esc}%"
    name_l = func.lower(DrugCatalog.product_name)
    active_l = func.lower(func.coalesce(DrugCatalog.active_ingredients, ""))

    stmt = (
        select(DrugCatalog)
        .where(
            name_l.like(contains, escape="\\")
            | active_l.like(contains, escape="\\")
        )
        .order_by(
            name_l.like(prefix, escape="\\").desc(),  # brand-name prefix hits first
            func.length(DrugCatalog.product_name),     # then the shortest / closest
            DrugCatalog.product_name,
        )
        .limit(limit)
    )

    rows = db.scalars(stmt).all()
    return DrugSearchOut(
        query=q,
        results=[
            DrugHit(
                name=r.product_name,
                salt_composition=r.salt_composition,
                active_ingredients=r.active_ingredients,
                drug_classes=r.drug_classes,
            )
            for r in rows
        ],
    )
