"""Integration checkpoint before Phase 6 — the whole pipeline as ONE continuous
chain for a single user session:

    scan  →  verdict  →  history  →  trends  →  nudge

Driven entirely through the real HTTP API (real OTP auth, real health vault, real
Postgres). The only things stubbed are the two external boundaries a demo can't
depend on: Open Food Facts (`openfoodfacts.fetch_product`) and the OCR engine
(`ocr.extract_text`). Every verdict, every scan_history row, every trend
aggregate and the nudge are computed for real.

What each link must prove:
  * scan     — GET /products/{barcode} returns ingredients+nutriments; a cache
               HIT on a re-scan doesn't re-hit OFF; a miss falls back to OCR.
  * verdict  — the ingredients/nutriments from the lookup feed POST /scan/verdict
               unchanged; allergen → hard-stop avoid; sodium+hypertension →
               caution; clean → safe.
  * history  — every verdict auto-wrote a row (no explicit "log" call); the
               product_name/barcode came from the lookup, not re-typed.
  * trends   — safe/caution/avoid totals equal the history counts equal the
               tiers the scan calls returned.
  * nudge    — the recurring sodium pattern (3 non-safe sodium scans) produced
               exactly one specific nudge, grounded in those history rows.

Run:  pytest tests/test_phase6_integration_checkpoint.py -v -s
"""

from __future__ import annotations

import io
from collections import Counter

import pytest
from PIL import Image
from sqlalchemy.orm import Session

from app.core.config import settings
from scripts.load_risk_tables import load_all

PHONE = "+919190000007"

A = "50000000000017"   # crackers — sodium, re-scanned 3x (the recurring pattern)
B = "50000000000024"   # cashew bar — tree-nut allergen → hard stop
C = "50000000000031"   # rolled oats — clean → safe
D = "50000000000099"   # not in OFF → OCR fallback

_OFF = {
    A: {
        "code": A,
        # only ONE recurring risk factor (sodium) so the nudge assertion is
        # unambiguous — a fattier / carbier cracker would rightly nudge on those
        # factors too.
        "product_name": "Sea-Salt Crackers",
        "brands": "Britannia",
        "ingredients_text": "Iodised salt",
        "ingredients": [{"text": "Iodised salt"}],
        "nutriments": {"sodium_100g": 1.4},
        "serving_size": "30 g",
    },
    B: {
        "code": B,
        "product_name": "Cashew Energy Bar",
        "brands": "Yogabar",
        "ingredients_text": "Roasted cashew, dates, cane sugar",
        "ingredients": [
            {"text": "Roasted cashew"},
            {"text": "Dates"},
            {"text": "Cane sugar"},
        ],
        "nutriments": {"sugars_100g": 24},
    },
    C: {
        "code": C,
        "product_name": "Rolled Oats",
        "brands": "Quaker",
        "ingredients_text": "Whole grain rolled oats",
        "ingredients": [{"text": "Whole grain rolled oats"}],
        "nutriments": {"fiber_100g": 10, "sugars_100g": 1, "sodium_100g": 0.004},
    },
    D: None,   # OFF miss
}


@pytest.fixture(scope="module", autouse=True)
def _ref(engine):
    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
    yield


def _png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (720, 240), "white").save(buf, format="PNG")
    return buf.getvalue()


def test_scan_verdict_history_trends_nudge_is_one_unbroken_chain(
    client, db, monkeypatch
):
    # ---- stub the two external boundaries ----------------------------------
    off_calls = {"n": 0}

    def _fake_fetch(barcode):
        off_calls["n"] += 1
        return _OFF[barcode]

    monkeypatch.setattr("app.services.openfoodfacts.fetch_product", _fake_fetch)
    monkeypatch.setattr(
        "app.services.ocr.extract_text",
        lambda _b: ("Whole grain wheat flour, cane sugar, sunflower oil", 0.93),
    )

    # ---- real auth --------------------------------------------------------
    dev = client.post("/api/v1/auth/request-otp", json={"phone": PHONE}).json()["dev_code"]
    token = client.post(
        "/api/v1/auth/verify-otp", json={"phone": PHONE, "code": dev}
    ).json()["access_token"]
    H = {"Authorization": f"Bearer {token}"}

    # ---- real vault: a user who reacts to sodium, is allergic to nuts,
    #      and is on an anticoagulant ------------------------------------
    assert client.post("/api/v1/me/conditions", headers=H,
                       json={"condition_name": "Hypertension"}).status_code == 201
    assert client.post("/api/v1/me/allergies", headers=H,
                       json={"allergen_name": "tree nuts"}).status_code == 201
    assert client.post("/api/v1/me/medications", headers=H,
                       json={"name": "Warfarin 5mg"}).status_code == 201

    verdict_tiers: list[str] = []
    nudge_events: list[tuple[int, str, int]] = []

    def scan_barcode(step: int, barcode: str, *, expect_cache: str | None):
        """The real client flow: look the barcode up, then hand the SAME
        ingredients/nutriments straight to /scan/verdict."""
        r = client.get(f"/api/v1/products/{barcode}", headers=H)
        if r.status_code == 404:
            assert r.json()["fallback"] == "ocr"
            img = _png()
            lab = client.post("/api/v1/products/scan-label", headers=H,
                              files={"file": ("label.png", img, "image/png")})
            assert lab.status_code == 200, lab.text
            ings = lab.json()["ingredients"]
            assert ings, "OCR fallback produced no ingredients"
            nut, name = {}, "Local bakery crackers"
        else:
            assert r.status_code == 200, r.text
            if expect_cache:
                assert r.headers.get("X-Cache") == expect_cache
            p = r.json()
            ings, nut, name = p["ingredients"], p["nutriments"], p["name"]
            assert ings, "product lookup returned no ingredients"

        v = client.post("/api/v1/scan/verdict", headers=H, json={
            "ingredients": ings, "nutriments": nut,
            "barcode": barcode, "product_name": name,
        })
        assert v.status_code == 200, v.text
        b = v.json()
        verdict_tiers.append(b["tier"])
        if b["nudge"]:
            nudge_events.append((step, b["nudge"]["factor"], b["nudge"]["hit_count"]))
        return b

    # ==== the session: 6 scans =========================================
    s1 = scan_barcode(1, A, expect_cache="MISS")   # sodium hit 1
    s2 = scan_barcode(2, B, expect_cache="MISS")   # tree-nut allergen
    s3 = scan_barcode(3, C, expect_cache="MISS")   # clean
    s4 = scan_barcode(4, D, expect_cache=None)     # OFF miss → OCR fallback
    s5 = scan_barcode(5, A, expect_cache="HIT")    # sodium hit 2 (served from cache)
    s6 = scan_barcode(6, A, expect_cache="HIT")    # sodium hit 3 → nudge

    # ---- link 1→2: scan feeds verdict -------------------------------------
    assert s1["tier"] == "caution", s1          # sodium ceiling for hypertension
    assert s2["hard_stop"] is True and s2["tier"] == "avoid" and s2["score"] == 0
    assert s2["reasons"][0]["kind"] == "allergen"
    assert s3["tier"] == "safe"
    assert s4["tier"] in {"safe", "caution", "avoid"}
    assert s5["tier"] == "caution" and s6["tier"] == "caution"
    # re-scanning A twice more never re-hit Open Food Facts
    assert off_calls["n"] == 4                   # A, B, C, D — once each

    # ---- link 3: every verdict auto-logged, most-recent-first -----------
    hist = client.get("/api/v1/history", headers=H, params={"limit": 100}).json()
    assert hist["total"] == 6
    names = [it["product_name"] for it in hist["items"]]
    assert names[0] == "Sea-Salt Crackers"       # most-recent-first
    # the names that reached history came straight from the lookups, not re-typed:
    #   3x the OFF product name, 1x the OCR-fallback name the client carried
    assert names.count("Sea-Salt Crackers") == 3
    assert "Local bakery crackers" in names      # scan → OCR → verdict → history
    hist_tiers = Counter(it["tier"] for it in hist["items"])
    assert hist_tiers == Counter(verdict_tiers)   # history == what scans returned

    # ---- link 4: trends aggregate the same session --------------------
    trends = client.get("/api/v1/analytics/trends", headers=H,
                        params={"tz": "UTC"}).json()
    assert trends["total_scans"] == 6
    for t in ("safe", "caution", "avoid"):
        wk = sum(w[t] for w in trends["weekly"])
        mo = sum(m[t] for m in trends["monthly"])
        assert wk == mo == hist_tiers[t], t
    assert 1 <= trends["diet_health_score"] <= 100

    # ---- link 5: the recurring pattern produced ONE specific nudge -------
    assert nudge_events == [(6, "sodium", 3)]
    nudges = client.get("/api/v1/nudges", headers=H).json()
    assert len(nudges["items"]) == 1
    n = nudges["items"][0]
    assert n["factor"] == "sodium" and n["hit_count"] == 3
    assert "odium" in n["message"] and len(n["message"]) > 40   # specific, not generic
    # grounded: >= 3 non-safe history rows whose key_reasons cite sodium
    grounded = [
        it for it in hist["items"]
        if it["tier"] in ("caution", "avoid")
        and any(kr.get("factor") == "sodium" for kr in it["key_reasons"])
    ]
    assert len(grounded) >= 3

    print("\n============ Phase 6 integration checkpoint ============")
    print("scans (GET /products → POST /scan/verdict) : 6")
    print(f"OFF fetch_product calls (cache working)    : {off_calls['n']}")
    print(f"verdict tiers                              : {dict(Counter(verdict_tiers))}")
    print(f"GET /history total={hist['total']}  tiers={dict(hist_tiers)}")
    print(f"GET /analytics/trends total_scans={trends['total_scans']}  "
          f"DHS={trends['diet_health_score']} ({trends['trend']})")
    print(f"GET /nudges  {[(x['factor'], x['hit_count']) for x in nudges['items']]}")
    print(f"   {n['message']}")
    print("chain intact: scan → verdict → history → trends → nudge")
