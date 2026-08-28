"""Phase 4.3 - the offline batch job that drains the unresolved_ingredients queue.

Verifies the two deliberately-separate steps:
  * ``classify_pending``  - curated-map classification, writes NOTHING to the
    CSVs, marks queue rows ``classified``, and never calls the network unless
    ``--use-api`` is passed.
  * ``merge_reviewed``    - only accept-marked rows land in
    ``llm_ingredient_tags.csv`` (+ an audit line), with method / confidence /
    rationale preserved; queue rows move to ``merged`` / ``rejected``.
"""

from __future__ import annotations

import csv

from sqlalchemy import select

from app.models import UnresolvedIngredient
from scripts import classify_unresolved as cu


def _queue(db, text: str, *, seen: int = 1, status: str = "pending"):
    row = UnresolvedIngredient(
        ingredient_text=text,
        normalized_text=text.strip().lower(),
        sample_product="8901234567890",
        times_seen=seen,
        status=status,
    )
    db.add(row)
    db.flush()
    return row


# ---------------------------------------------------------------- classify step
def test_classify_pending_uses_curated_map_and_writes_no_csv(db, tmp_path, monkeypatch):
    import httpx

    monkeypatch.setattr(
        httpx, "post",
        lambda *a, **k: (_ for _ in ()).throw(AssertionError("no API call without --use-api")),
    )

    _queue(db, "edible vegetable oil", seen=9)
    _queue(db, "zzz unknowable substance", seen=3)

    rows = cu.classify_pending(db, use_api=False)
    by_token = {r["normalized_text"]: r for r in rows}

    assert by_token["edible vegetable oil"]["method"] == "llm-curated"
    assert by_token["edible vegetable oil"]["risk_compounds"] == "saturated_fat"
    assert float(by_token["edible vegetable oil"]["confidence"]) == 0.4
    assert by_token["zzz unknowable substance"]["method"] == "unclassified"
    assert by_token["zzz unknowable substance"]["risk_compounds"] == ""

    # queue rows are now 'classified', so a second run doesn't re-list them
    for r in db.scalars(select(UnresolvedIngredient)).all():
        assert r.status == "classified"
    assert cu.classify_pending(db, use_api=False) == []

    out = tmp_path / "review.csv"
    cu.write_review_csv(rows, str(out))
    assert out.exists()
    header = out.read_text(encoding="utf-8").splitlines()[0]
    assert header.split(",") == cu.REVIEW_FIELDS


def test_classify_min_seen_filter(db):
    _queue(db, "rare token", seen=1)
    _queue(db, "frequent token", seen=5)
    rows = cu.classify_pending(db, min_seen=3)
    assert [r["normalized_text"] for r in rows] == ["frequent token"]


def test_classify_api_path_parses_and_clamps(db, monkeypatch):
    import httpx

    class _Resp:
        def raise_for_status(self):
            pass

        def json(self):
            return {
                "content": [
                    {"type": "text",
                     "text": 'ok {"risk_compounds": ["sodium", "bogus_tag"], '
                             '"confidence": 1.5, "rationale": "salt-heavy blend"}'}
                ]
            }

    monkeypatch.setattr(httpx, "post", lambda *a, **k: _Resp())
    _queue(db, "some novel seasoning base", seen=2)

    rows = cu.classify_pending(
        db, use_api=True, api_key="sk-ant-test", model="claude-haiku-4-5-20251001"
    )
    (row,) = rows
    assert row["method"] == "llm-api"
    assert row["model"] == "claude-haiku-4-5-20251001"
    assert row["risk_compounds"] == "sodium"          # bogus_tag dropped
    assert float(row["confidence"]) == 0.9            # clamped from 1.5
    assert row["rationale"] == "salt-heavy blend"


# ------------------------------------------------------------------- merge step
def _seed_data_dir(tmp_path):
    d = tmp_path / "data_prep"
    d.mkdir()
    with open(d / "llm_ingredient_tags.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f, fieldnames=["ingredient_clean", "risk_compounds", "confidence",
                           "method", "rationale"])
        w.writeheader()
        w.writerow({"ingredient_clean": "already known token", "risk_compounds": "sodium",
                    "confidence": "0.6", "method": "llm", "rationale": "seed"})
    with open(d / "food_ingredient_method_log.csv", "w", encoding="utf-8", newline="") as f:
        csv.DictWriter(
            f, fieldnames=["food_id", "source_file", "ingredient_raw",
                           "ingredient_clean", "risk_compounds", "method"]).writeheader()
    return d


def test_merge_reviewed_only_accepts_marked_rows(db, tmp_path):
    data_dir = _seed_data_dir(tmp_path)
    _queue(db, "brand new token", status="classified")
    _queue(db, "already known token", status="classified")
    _queue(db, "declined token", status="classified")

    reviewed = tmp_path / "reviewed.csv"
    with open(reviewed, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cu.REVIEW_FIELDS)
        w.writeheader()
        w.writerow({"ingredient_text": "brand new token", "normalized_text": "brand new token",
                    "times_seen": 4, "sample_product": "x", "risk_compounds": "rapid_carb",
                    "confidence": "0.65", "method": "llm-curated", "model": "",
                    "rationale": "refined starch base", "accept": "y"})
        w.writerow({"ingredient_text": "already known token",
                    "normalized_text": "already known token", "times_seen": 2,
                    "sample_product": "x", "risk_compounds": "sodium", "confidence": "0.6",
                    "method": "llm-curated", "model": "", "rationale": "dup", "accept": "yes"})
        w.writerow({"ingredient_text": "declined token", "normalized_text": "declined token",
                    "times_seen": 1, "sample_product": "x", "risk_compounds": "caffeine",
                    "confidence": "0.4", "method": "llm-curated", "model": "",
                    "rationale": "not sure", "accept": "n"})

    counts = cu.merge_reviewed(db, str(reviewed), str(data_dir))
    assert counts == {"accepted": 1, "rejected": 1, "skipped_already_present": 1}

    with open(data_dir / "llm_ingredient_tags.csv", encoding="utf-8") as f:
        merged = list(csv.DictReader(f))
    new = [r for r in merged if r["ingredient_clean"] == "brand new token"]
    assert len(new) == 1
    assert new[0]["risk_compounds"] == "rapid_carb"
    assert new[0]["confidence"] == "0.65"
    assert new[0]["method"] == "llm-curated"
    assert new[0]["rationale"] == "refined starch base"
    # 'already known token' not duplicated
    assert sum(1 for r in merged if r["ingredient_clean"] == "already known token") == 1

    with open(data_dir / "food_ingredient_method_log.csv", encoding="utf-8") as f:
        log = list(csv.DictReader(f))
    assert any(r["food_id"] == "QUEUE" and r["ingredient_clean"] == "brand new token"
               for r in log)

    status = {r.normalized_text: r.status
              for r in db.scalars(select(UnresolvedIngredient)).all()}
    assert status["brand new token"] == "merged"
    assert status["declined token"] == "rejected"
    assert status["already known token"] == "classified"  # accepted but a dup -> untouched


def test_module_has_no_import_time_side_effects():
    # importing the batch job must not open a DB connection or hit the network
    import importlib

    mod = importlib.reload(cu)
    assert hasattr(mod, "classify_pending")
    assert hasattr(mod, "merge_reviewed")
