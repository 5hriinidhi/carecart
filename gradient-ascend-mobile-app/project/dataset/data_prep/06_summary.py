"""Step 6 - roll up counts and the manual-curation to-do list into SUMMARY.md."""
import csv, os, collections, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
def p(n): return os.path.join(HERE, n)
def rows(n):
    with open(p(n), encoding="utf-8") as f:
        return list(csv.DictReader(f))
def nrows(n):
    try:
        with open(p(n), encoding="utf-8") as f:
            return sum(1 for _ in f) - 1
    except FileNotFoundError:
        return None

# ---------- food tagging ----------
log = rows("food_ingredient_method_log.csv")
mlog = collections.Counter(r["method"] for r in log)
kw   = mlog.get("keyword", 0)
llm  = mlog.get("llm", 0)
tagged = kw + llm
tags = rows("food_risk_tags.csv")
tag_method = collections.Counter(r["method"] for r in tags)
tag_rc     = collections.Counter(r["risk_compound"] for r in tags)
foods_if = len({r["food_id"] for r in tags if r["food_id"].startswith("IF-")})
foods_pf = len({r["food_id"] for r in tags if r["food_id"].startswith("PF-")})

unres = rows("unresolved_ingredients.csv")
top20 = unres[:20]

# ---------- drug classes ----------
dc = rows("active_ingredient_classes.csv")
dc_method = collections.Counter()
for r in dc:
    dc_method[r["method"]] += int(r["medicine_count"])
dc_dist_method = collections.Counter(r["method"] for r in dc)
unmapped_ai = rows("unmapped_active_ingredients.csv")
irules = rows("interaction_rules.csv")
sev = collections.Counter(r["severity"] for r in irules)
not_in_ds = sorted({r["drug_class"] for r in irules if r["drug_class_present_in_dataset"] == "no"})

md = []
w = md.append
w("# CareCart data-prep - run summary")
w("")
w(f"_Generated {datetime.date.today().isoformat()} by the scripts in this folder. "
  "One-time offline job; not part of the app._")
w("")
w("## 1. Row counts per output file")
w("")
w("| file | rows | grain |")
w("|---|--:|---|")
for f, grain in [
    ("risk_compounds.csv", "risk-compound category (hand-authored reference)"),
    ("ingredient_aliases.csv", "keyword alias -> risk_compound (hand-authored, reviewable)"),
    ("llm_ingredient_tags.csv", "ingredient token classified by LLM fallback (method=llm)"),
    ("food_risk_tags.csv", "(food_id, risk_compound) - THE STEP 3 DELIVERABLE"),
    ("food_ingredient_method_log.csv", "(food_id, ingredient) audit trail - spot-check LLM rows here"),
    ("unresolved_ingredients.csv", "distinct ingredient tokens still untagged"),
    ("drug_class_lookup.csv", "active_ingredient -> drug_class (hand-authored, reviewable)"),
    ("drug_class_stem_rules.csv", "suffix/prefix stem rule -> drug_class (reviewable)"),
    ("llm_drug_classes.csv", "active_ingredient classified by LLM fallback (method=llm)"),
    ("drug_classes.csv", "(medicine_id, active_ingredient, drug_class, method) - THE STEP 4 DELIVERABLE"),
    ("active_ingredient_classes.csv", "distinct active_ingredient -> drug_class + method"),
    ("unmapped_active_ingredients.csv", "distinct active ingredients still unmapped"),
    ("interaction_rules.csv", "DRAFT (drug_class x risk_compound) rules - NEEDS CLINICAL REVIEW"),
]:
    n = nrows(f)
    w(f"| `{f}` | {n if n is not None else 'n/a'} | {grain} |")
w("")
w(f"Source inputs: `indian_food.csv` (255 rows), `packaged_foods_india.csv` (852 rows), "
  "`medicine_data.csv` (195,605 rows, unzipped from `medicine_data.csv.zip`).")
w("")

w("## 2. Food tagging - keyword vs LLM fallback")
w("")
w("**Per ingredient mention** (from `food_ingredient_method_log.csv`):")
w("")
w("| method | mentions | share of all parsed | share of *tagged* |")
w("|---|--:|--:|--:|")
total_ing = sum(mlog.values())
for m in ["keyword", "llm", "benign(llm-reviewed)", "unresolved", "benign"]:
    c = mlog.get(m, 0)
    of_tagged = f"{100*c/tagged:.1f}%" if m in ("keyword", "llm") and tagged else "-"
    w(f"| {m} | {c} | {100*c/total_ing:.1f}% | {of_tagged} |")
w(f"| **total parsed** | **{total_ing}** | | |")
w("")
w(f"- Of ingredient mentions that received a risk tag: **{100*kw/tagged:.1f}% keyword / "
  f"{100*llm/tagged:.1f}% LLM**.")
w("")
w("**Per (food, risk_compound) tag row** (`food_risk_tags.csv`, "
  f"{len(tags)} rows; {foods_if} Indian + {foods_pf} packaged foods tagged):")
w("")
w("| method | tag rows | share |")
w("|---|--:|--:|")
for m, c in tag_method.most_common():
    w(f"| {m} | {c} | {100*c/len(tags):.1f}% |")
w("")
w("Risk compounds by tag frequency:")
w("")
w("| risk_compound | tag rows |")
w("|---|--:|")
for k, c in tag_rc.most_common():
    w(f"| {k} | {c} |")
w("")

w("## 3. Top 20 ingredients still untagged (add these to `ingredient_aliases.csv`)")
w("")
w(f"{len(unres)} distinct tokens remain unresolved after both passes "
  f"(mostly single-occurrence). The 20 most common:")
w("")
w("| # | ingredient (cleaned) | occurrences | example food |")
w("|--:|---|--:|---|")
for i, r in enumerate(top20, 1):
    w(f"| {i} | {r['ingredient_clean']} | {r['occurrences']} | {r['example_food_name']} |")
w("")
w("Every token that occurred **>=2 times** was consumed by the LLM fallback pass "
  "(either given a tag or explicitly reviewed as benign), so the residue here is "
  "all single-occurrence - mostly home-recipe wording in `indian_food.csv` "
  "(`ladies finger`, `shimla mirch`, `naan bread`, `axone`, `pork`). Worth aliasing "
  "by hand: `naan bread`/`loaf bread` -> gluten_allergen+rapid_carb, `tomato sauce` "
  "-> sodium, `black lentils`/`mung bean` -> benign.")
w("")
w("### LLM-assigned food tags to spot-check")
w("")
llm_tag_rows = [r for r in rows('llm_ingredient_tags.csv') if r['risk_compounds'] != 'none']
tok_food_ct = collections.Counter()
for r in log:
    if r['method'] == 'llm':
        tok_food_ct[r['ingredient_clean']] += 1
w(f"{len(llm_tag_rows)} distinct tokens were given a risk tag by the LLM pass "
  "(method=llm). The ones touching the most foods:")
w("")
w("| ingredient token | risk_compounds (LLM) | foods affected | rationale |")
w("|---|---|--:|---|")
seen = {r['ingredient_clean']: r for r in llm_tag_rows}
for tok, c in tok_food_ct.most_common(20):
    if tok in seen:
        r = seen[tok]
        w(f"| {tok} | {r['risk_compounds']} | {c} | {r['rationale']} |")
w("")
w("Full audit trail: `food_ingredient_method_log.csv` (filter `method == llm`).")
w("")

w("## 4. Drug classification - method mix")
w("")
w(f"`drug_classes.csv`: {nrows('drug_classes.csv')} (medicine, active-ingredient) rows "
  f"from 195,605 medicines; {len(dc)} distinct active ingredients.")
w("")
w("| method | (medicine, active) rows | share |")
w("|---|--:|--:|")
tot = sum(dc_method.values())
for m, c in dc_method.most_common():
    w(f"| {m} | {c} | {100*c/tot:.1f}% |")
w("")
w("| method | distinct active ingredients | share |")
w("|---|--:|--:|")
tot2 = sum(dc_dist_method.values())
for m, c in dc_dist_method.most_common():
    w(f"| {m} | {c} | {100*c/tot2:.1f}% |")
w("")
w(f"- **{100*(tot-dc_method.get('unmapped',0))/tot:.1f}%** of (medicine, active) rows "
  f"were classified; **{dc_dist_method.get('unmapped',0)}** distinct ingredients remain unmapped.")
w("")
w("### Active ingredients still unmapped (add to `drug_class_lookup.csv`)")
w("")
w("| active_ingredient | medicine_count | top sub_category |")
w("|---|--:|---|")
for r in unmapped_ai[:25]:
    w(f"| {r['active_ingredient']} | {r['medicine_count']} | {r['top_sub_category']} |")
if len(unmapped_ai) > 25:
    w(f"| ...{len(unmapped_ai)-25} more | | |")
w("")
w("These are mostly comma-split fragments of multi-word names "
  "(`human`, `recombinant`, `oral)`, `w-135)`, `and 18) vaccine`) - fix by making "
  "the salt-composition splitter paren-aware, not by adding aliases.")
w("")

w("## 5. Draft interaction rules (STEP 5 - NOT VALIDATED)")
w("")
w(f"`interaction_rules.csv`: **{len(irules)} candidate rows**, every one flagged "
  "`review_status = NEEDS CLINICAL REVIEW`.")
w("")
w(f"- Severity mix: " + ", ".join(f"{k} {v}" for k, v in sev.most_common()))
w(f"- {len(irules) - len(not_in_ds)} rules reference a drug_class that appears in this "
  f"medicine dataset; {len(not_in_ds)} are forward-looking "
  "(`drug_class_present_in_dataset = no`) because the dataset has almost no "
  "cardiology drugs - no warfarin, digoxin, loop diuretics, spironolactone, "
  "non-dihydropyridine CCBs, pioglitazone, clonidine.")
w("")
w("> This table was seeded from well-known food-drug interaction patterns as a")
w("> starting point. It has **not** been checked by a pharmacist or clinician.")
w("> Do not surface it in the app or treat any row as authoritative until it has")
w("> been reviewed, and expect rows to be edited, downgraded, or removed.")
w("")

w("## 6. Known limitations / follow-ups")
w("")
w("- **Nutrient columns unused.** `packaged_foods_india.csv` has real "
  "`Sodium_mg`, `Sugar_g`, `Saturated_Fat_g` etc.; tagging currently keys off the "
  "ingredient text only. A numeric threshold pass would make `sodium` / "
  "`added_sugar` / `saturated_fat` tags quantitative and catch items whose "
  "ingredient list is vague.")
w("- **`edible vegetable oil`** (123 mentions) is tagged `saturated_fat` at low "
  "confidence 0.4 - in Indian packaged food it is usually palm, but confirm.")
w("- **`lecithin`** is assumed soy-derived (common in India) and tagged "
  "`soy_allergen` 0.7 - sunflower lecithin exists; review.")
w("- **Coconut** is deliberately NOT tagged `nut_allergen` (low clinical "
  "cross-reactivity); revisit per user allergy profile.")
w("- **Allergen tags are ingredient-derived only** - 'may contain' / shared-line "
  "cross-contamination statements are not parsed.")
w("- **salt_composition splitter** is not parenthesis-aware, so a few vaccine / "
  "combination names split on internal commas into fragments (see section 4).")
w("- **sub_category** in `medicine_data.csv` often describes the combination "
  "product, not the molecule (e.g. amitriptyline filed under 'Other Anti "
  "Malarials'); it is used only as a last-resort, low-trust class signal.")

with open(p("SUMMARY.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(md) + "\n")
print("wrote", p("SUMMARY.md"))
print("\n".join(md))
