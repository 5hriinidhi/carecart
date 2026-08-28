# CareCart data-prep (one-time offline job)

Turns the three raw datasets in `../` into reference tables the app can use to
flag food-drug interactions. **Not part of the running app** - run it by hand,
review the outputs, commit the CSVs.

## Inputs (in `../`)
| file | rows | used for |
|---|--:|---|
| `indian_food.csv` | 255 | ingredient text -> risk tags |
| `packaged_foods_india.csv` | 852 | ingredient text -> risk tags |
| `medicine_data.csv.zip` -> `medicine_data.csv` | 195,605 | `salt_composition` -> drug classes |

`medicine_data.csv.zip` and its 354 MB unzipped form are **not** committed
(see `.gitignore`) - obtain the zip separately and drop it in `../`.
`04_drug_classes.py` unzips it to a temp dir automatically; delete that temp
copy when done. `drug_classes.csv` and `food_ingredient_method_log.csv` are also
gitignored - rebuild them by running `03`/`04`.

## Run order
```
python make_llm_ingredient_tags.py   # (re)build LLM fallback for foods   [optional, already committed]
python 03_tag_foods.py               # -> food_risk_tags.csv + audit log + unresolved list
python make_drug_class_lookup.py     # (re)build drug_class_lookup.csv + drug_class_stem_rules.csv
python make_llm_drug_classes.py      # (re)build LLM fallback for drugs   [optional, already committed]
python 04_drug_classes.py            # -> drug_classes.csv + active_ingredient_classes.csv + unmapped list
python 05_interaction_rules.py       # -> interaction_rules.csv  (DRAFT - NEEDS CLINICAL REVIEW)
python 06_summary.py                 # -> SUMMARY.md
```
`03` and `04` are two-pass: run once to produce the `unresolved_*` / `unmapped_*`
lists, review them, extend the `llm_*` file (or the hand tables), re-run.

All scripts need `PYTHONUTF8=1` on Windows (rupee sign / BOM in the source CSVs).

## Files

### Hand-authored reference (review + extend these)
| file | what |
|---|---|
| `risk_compounds.csv` | 26 food-chemistry categories relevant to drug interactions |
| `ingredient_aliases.csv` | `alias -> risk_compound` keyword dictionary (`match_type` = substring/word) |
| `risk_nutrient_thresholds.csv` | numeric counterpart: per-100 g nutrient band (`nutrient_key,min_value`) -> `risk_compound` + `confidence` + `rationale`. FSA front-of-pack "high"/"medium" levels for sodium / sugar / saturated fat |
| `drug_class_lookup.csv` | `active_ingredient -> drug_class`, ~1000 entries |
| `drug_class_stem_rules.csv` | ordered suffix/prefix rules (`-pril` -> ACE inhibitor, `cef-` -> Cephalosporin, ...) |
| `condition_diet_rules.csv` | per-condition dietary rules (Phase 4.4): `kind` = `nutrient_ceiling` (per-100 g limit) or `risk_compound` (compound to avoid) + `severity` |
| `allergen_aliases.csv` | allergy free-text -> allergen `risk_compound` (Phase 4.4). A match is a HARD STOP in the verdict, not a deduction |

### Consumed at runtime (Phases 4.3 + 4.4)

`backend/scripts/load_risk_tables.py` loads `risk_compounds.csv`,
`ingredient_aliases.csv`, `llm_ingredient_tags.csv`,
`risk_nutrient_thresholds.csv`, `food_risk_tags.csv`, `interaction_rules.csv`,
`drug_class_lookup.csv` + `llm_drug_classes.csv`, `drug_class_stem_rules.csv`,
`condition_diet_rules.csv` and `allergen_aliases.csv` into Postgres.

- `POST /products/resolve-risks` (4.3) resolves ingredients against the alias /
  threshold tables only — **no LLM call at runtime**. Ingredients that match
  nothing are queued in `unresolved_ingredients`;
  `backend/scripts/classify_unresolved.py` is the offline batch job that drains
  that queue with the same LLM-fallback approach as `make_llm_ingredient_tags.py`
  and, after human review, appends accepted rows to `llm_ingredient_tags.csv`
  (re-run `03_tag_foods.py` + `load_risk_tables.py` to deploy).
- `POST /scan/verdict` (4.4) scores those resolved compounds + the product's
  nutriments against the signed-in user's stored conditions / allergies / active
  medications using `interaction_rules.csv` (drug_class × risk_compound),
  `condition_diet_rules.csv` and `allergen_aliases.csv`. `interaction_rules.csv`
  is still a clinician-review DRAFT (see below).

### LLM fallback (method=llm; spot-check these)
| file | what |
|---|---|
| `make_llm_ingredient_tags.py` / `llm_ingredient_tags.csv` | Claude's classification of food tokens the keyword pass missed |
| `make_llm_drug_classes.py` / `llm_drug_classes.csv` | Claude's classification of active ingredients the lookup+stems missed |

No external API is called - "LLM" = the Claude session that built this, encoded as
an editable Python dict. Swap in a real API call if you want.

### Outputs
| file | grain | notes |
|---|---|---|
| `food_risk_tags.csv` | `food_id, risk_compound, confidence, method` | **step 3 deliverable**. `food_id` = `IF-0001` (indian_food row order) or `PF-<S.No>` |
| `food_ingredient_method_log.csv` | one row per parsed ingredient | audit trail; filter `method == llm` to spot-check |
| `unresolved_ingredients.csv` | untagged tokens by frequency | manual-curation to-do for `ingredient_aliases.csv` |
| `drug_classes.csv` | `medicine_id, active_ingredient, drug_class, method` (+ product_name, salt) | **step 4 deliverable**. `medicine_id` = `MD-000001` by row order |
| `active_ingredient_classes.csv` | distinct ingredient -> class + method + count | review view |
| `unmapped_active_ingredients.csv` | still-unmapped actives | manual-curation to-do for `drug_class_lookup.csv` |
| `interaction_rules.csv` | `drug_class, risk_compound, severity, mechanism, dietary_guidance, evidence_strength, example_drugs, drug_class_present_in_dataset, review_status` | **step 5 - DRAFT.** every row `review_status = NEEDS CLINICAL REVIEW` |
| `SUMMARY.md` | run report | counts, keyword-vs-LLM %, curation lists, limitations |

## interaction_rules.csv - read this

Seeded from well-documented food-drug interaction patterns (ACE inhibitor +
potassium, warfarin + vitamin K, MAOI/linezolid + tyramine, fluoroquinolone +
dairy calcium, metronidazole + alcohol, ...). It is a **starting point for a
clinician**, not a validated table. Do not surface it in the app or treat any
row as safe until a pharmacist/clinician has reviewed every row. Expect rows to
be edited, downgraded, or deleted.
