"""Phase 5 Check - does the feedback loop close?

Two weeks of realistic usage for ONE user, driven entirely through the real API
(OTP auth -> vault -> POST /scan/verdict for every scan; the nudge detector runs
inside each real request). Only the *timestamps* are compressed afterwards
(`UPDATE scan_history.scanned_at`) so the 16 scans land across ~14 days / two
weekly buckets - no data is seeded, every verdict / history row / nudge was
computed for real.

Then: GET /history, GET /analytics/trends and GET /nudges must all agree -
notably the trends dashboard's safe/caution/avoid totals equal the actual
counts in history, which equal the tiers the scan calls returned.

Run:  pytest tests/test_phase5_check.py -v -s
"""

from __future__ import annotations

import datetime as dt
from collections import Counter

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import decode_access_token
from scripts.load_risk_tables import load_all

PHONE = "+919180000001"

PRODUCTS = {
    "clean": (["Rolled oats"], {"sugars_g_100g": 1, "sodium_mg_100g": 5, "fiber_g_100g": 10}),
    "salty": (["Iodised salt", "Gram flour"], {"sodium_mg_100g": 1200}),
    "sugary": (["Wheat flour", "Sugar"], {"sugars_g_100g": 30}),
    "greens_salt": (["Broccoli", "Iodised salt"], {"sodium_mg_100g": 1300}),
}

# (day 1..14, product) — a realistic fortnight with a deliberate recurring
# SODIUM pattern (salty + greens_salt), plus safe scans and a couple of others.
PLAN = [
    (1, "clean"), (1, "salty"),
    (2, "sugary"),
    (3, "clean"), (3, "salty"),
    (4, "greens_salt"),           # 3rd non-safe sodium scan -> nudge fires here
    (5, "clean"),
    (6, "salty"),
    (7, "clean"),
    (8, "sugary"),
    (9, "clean"),
    (10, "salty"),
    (11, "clean"),
    (12, "greens_salt"),
    (13, "clean"),
    (14, "clean"),
]


@pytest.fixture(scope="module", autouse=True)
def _ref(engine):
    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
    yield


def test_two_weeks_history_trends_nudges_all_agree(client, db):
    # ---- real auth ----
    dev_code = client.post("/api/v1/auth/request-otp", json={"phone": PHONE}).json()["dev_code"]
    token = client.post(
        "/api/v1/auth/verify-otp", json={"phone": PHONE, "code": dev_code}
    ).json()["access_token"]
    H = {"Authorization": f"Bearer {token}"}
    uid = decode_access_token(token)["sub"]

    # ---- real vault ----
    for cond in ("Hypertension", "Type 2 diabetes"):
        assert client.post("/api/v1/me/conditions", headers=H,
                           json={"condition_name": cond}).status_code == 201
    assert client.post("/api/v1/me/medications", headers=H,
                       json={"name": "Warfarin 5mg"}).status_code == 201

    now = dt.datetime.now(dt.UTC)

    def day_ts(day: int) -> dt.datetime:
        return now - dt.timedelta(days=14 - day, hours=2)

    verdict_tiers: list[str] = []
    nudge_events: list[tuple[int, str, int]] = []

    for i, (day, key) in enumerate(PLAN, start=1):
        ings, nut = PRODUCTS[key]
        r = client.post("/api/v1/scan/verdict", headers=H, json={
            "ingredients": ings, "nutriments": nut, "product_name": f"{key} #{i}",
        })
        assert r.status_code == 200, r.text
        b = r.json()
        verdict_tiers.append(b["tier"])
        if b["nudge"]:
            nudge_events.append((i, b["nudge"]["factor"], b["nudge"]["hit_count"]))

        # compress time: place THIS scan on its simulated day
        db.execute(
            text("UPDATE scan_history SET scanned_at = :ts WHERE id = "
                 "(SELECT id FROM scan_history WHERE user_id = :u ORDER BY seq DESC LIMIT 1)"),
            {"ts": day_ts(day), "u": uid},
        )
        db.commit()

    # ---- pull the three screens' data ----
    hist = client.get("/api/v1/history", headers=H, params={"limit": 100}).json()
    trends = client.get("/api/v1/analytics/trends", headers=H, params={"tz": "UTC"}).json()
    nudges = client.get("/api/v1/nudges", headers=H).json()

    hist_tiers = Counter(it["tier"] for it in hist["items"])
    vt = Counter(verdict_tiers)
    wk = {t: sum(w[t] for w in trends["weekly"]) for t in ("safe", "caution", "avoid")}
    mo = {t: sum(m[t] for m in trends["monthly"]) for t in ("safe", "caution", "avoid")}

    print("\n================= Phase 5 Check =================")
    print(f"scans run through POST /scan/verdict : {len(PLAN)}")
    print(f"verdict tiers returned              : {dict(vt)}")
    print(f"GET /history  total={hist['total']}  tiers={dict(hist_tiers)}")
    print(f"GET /analytics/trends  total_scans={trends['total_scans']}  "
          f"DHS={trends['diet_health_score']} ({trends['trend']})")
    for w in trends["weekly"]:
        print(f"   week {w['period_start']} {w['label']:7} n={w['scans']} "
              f"s/c/a={w['safe']}/{w['caution']}/{w['avoid']}")
    print(f"   weekly totals  s/c/a = {wk['safe']}/{wk['caution']}/{wk['avoid']}")
    print(f"   monthly totals s/c/a = {mo['safe']}/{mo['caution']}/{mo['avoid']}")
    print(f"GET /nudges  items={len(nudges['items'])}  "
          f"{[(n['factor'], n['hit_count']) for n in nudges['items']]}")
    print(f"   nudge fired during scanning at: {nudge_events}")
    if nudges["items"]:
        print(f"   message: {nudges['items'][0]['message']}")

    # ---------- CONSISTENCY: the loop closes ----------
    # 1. history has every scan
    assert hist["total"] == len(PLAN) == 16
    assert sum(hist_tiers.values()) == 16

    # 2. history tiers == the tiers the scan calls actually returned
    assert hist_tiers == vt

    # 3. trends' weekly safe/caution/avoid totals == history == verdicts
    for t in ("safe", "caution", "avoid"):
        assert wk[t] == hist_tiers[t] == vt[t], t
    # explicit: the caution count matches across all three
    assert wk["caution"] == hist_tiers["caution"] == verdict_tiers.count("caution") == 6

    # 4. trends scan totals line up (weekly and monthly)
    assert trends["total_scans"] == 16
    assert sum(w["scans"] for w in trends["weekly"]) == 16
    assert sum(m["scans"] for m in trends["monthly"]) == 16
    assert mo == {"safe": 8, "caution": 6, "avoid": 2}
    assert 1 <= len(trends["weekly"]) <= 3
    assert trends["diet_health_score"] and 0 <= trends["diet_health_score"] <= 100

    # 5. the recurring sodium pattern produced exactly one nudge, at the 3rd hit
    assert nudge_events == [(6, "sodium", 3)]
    assert len(nudges["items"]) == 1
    n = nudges["items"][0]
    assert n["factor"] == "sodium" and n["hit_count"] == 3
    assert "Sodium" in n["message"]
    # added_sugar (2 scans) and vitamin_k (2 scans) never reached the threshold
    assert {x["factor"] for x in nudges["items"]} == {"sodium"}

    # 6. and the nudge is grounded in real history: >= 3 non-safe scans whose
    #    key_reasons include factor "sodium"
    sodium_nonsafe = [
        it for it in hist["items"]
        if it["tier"] in ("caution", "avoid")
        and any(kr.get("factor") == "sodium" for kr in it["key_reasons"])
    ]
    assert len(sodium_nonsafe) >= 3

    print("\nOK: history <-> trends <-> nudges all consistent; the feedback loop closes.")
