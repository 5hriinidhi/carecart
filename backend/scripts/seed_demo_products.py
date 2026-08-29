"""Seed a handful of deterministic products into the OFF lookup cache.

The Flutter integration test (`mobile/integration_test/full_journey_test.dart`)
drives `GET /products/{barcode}` through the real UI. Those rows would otherwise
be fetched live from Open Food Facts — flaky and non-deterministic in CI. Seeding
them with `refreshed_at = now()` makes the endpoint serve straight from Postgres
and never touch OFF.

    python -m scripts.seed_demo_products
"""

from __future__ import annotations

import datetime as dt

from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db.session import SessionLocal
from app.models import Product

# barcode -> normalised product (matches app.services.openfoodfacts.normalize output)
DEMO = {
    "20000000001": {
        "name": "Roasted Cashew Bar",
        "brand": "DemoFoods",
        "ingredients_text": "Roasted cashew, dates, cane sugar",
        "ingredients": ["Roasted cashew", "Dates", "Cane sugar"],
        "nutriments": {"sugars_g_100g": 24.0},
        "serving_size": "35 g",
    },
    "20000000002": {
        "name": "Rolled Oats",
        "brand": "DemoFoods",
        "ingredients_text": "Whole grain rolled oats",
        "ingredients": ["Whole grain rolled oats"],
        "nutriments": {"fiber_g_100g": 10.0, "sugars_g_100g": 1.0},
        "serving_size": "40 g",
    },
    "20000000003": {
        "name": "Sea-Salt Crackers",
        "brand": "DemoFoods",
        "ingredients_text": "Wheat flour, iodised salt, palm oil",
        "ingredients": ["Wheat flour", "Iodised salt", "Palm oil"],
        "nutriments": {"sodium_mg_100g": 1400.0, "saturated_fat_g_100g": 9.0},
        "serving_size": "30 g",
    },
}


def main() -> int:
    now = dt.datetime.now(dt.UTC)
    db = SessionLocal()
    try:
        for barcode, p in DEMO.items():
            values = {
                "barcode": barcode,
                "off_status": "found",
                "source": "openfoodfacts",
                "refreshed_at": now,
                **p,
            }
            db.execute(
                pg_insert(Product)
                .values(**values)
                .on_conflict_do_update(index_elements=["barcode"], set_=values)
            )
        db.commit()
        print(f"seeded {len(DEMO)} demo products: {', '.join(DEMO)}")
    finally:
        db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
