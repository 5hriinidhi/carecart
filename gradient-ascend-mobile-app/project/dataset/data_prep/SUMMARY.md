# CareCart data-prep - run summary

_Generated 2026-08-27 by the scripts in this folder. One-time offline job; not part of the app._

## 1. Row counts per output file

| file | rows | grain |
|---|--:|---|
| `risk_compounds.csv` | 26 | risk-compound category (hand-authored reference) |
| `ingredient_aliases.csv` | 367 | keyword alias -> risk_compound (hand-authored, reviewable) |
| `llm_ingredient_tags.csv` | 671 | ingredient token classified by LLM fallback (method=llm) |
| `food_risk_tags.csv` | 4290 | (food_id, risk_compound) - THE STEP 3 DELIVERABLE |
| `food_ingredient_method_log.csv` | 11216 | (food_id, ingredient) audit trail - spot-check LLM rows here |
| `unresolved_ingredients.csv` | 915 | distinct ingredient tokens still untagged |
| `drug_class_lookup.csv` | 1039 | active_ingredient -> drug_class (hand-authored, reviewable) |
| `drug_class_stem_rules.csv` | 74 | suffix/prefix stem rule -> drug_class (reviewable) |
| `llm_drug_classes.csv` | 388 | active_ingredient classified by LLM fallback (method=llm) |
| `drug_classes.csv` | 293546 | (medicine_id, active_ingredient, drug_class, method) - THE STEP 4 DELIVERABLE |
| `active_ingredient_classes.csv` | 1000 | distinct active_ingredient -> drug_class + method |
| `unmapped_active_ingredients.csv` | 17 | distinct active ingredients still unmapped |
| `interaction_rules.csv` | 129 | DRAFT (drug_class x risk_compound) rules - NEEDS CLINICAL REVIEW |

Source inputs: `indian_food.csv` (255 rows), `packaged_foods_india.csv` (852 rows), `medicine_data.csv` (195,605 rows, unzipped from `medicine_data.csv.zip`).

## 2. Food tagging - keyword vs LLM fallback

**Per ingredient mention** (from `food_ingredient_method_log.csv`):

| method | mentions | share of all parsed | share of *tagged* |
|---|--:|--:|--:|
| keyword | 4893 | 43.6% | 81.9% |
| llm | 1078 | 9.6% | 18.1% |
| benign(llm-reviewed) | 2651 | 23.6% | - |
| unresolved | 915 | 8.2% | - |
| benign | 1679 | 15.0% | - |
| **total parsed** | **11216** | | |

- Of ingredient mentions that received a risk tag: **81.9% keyword / 18.1% LLM**.

**Per (food, risk_compound) tag row** (`food_risk_tags.csv`, 4290 rows; 240 Indian + 845 packaged foods tagged):

| method | tag rows | share |
|---|--:|--:|
| keyword | 3859 | 90.0% |
| llm | 431 | 10.0% |

Risk compounds by tag frequency:

| risk_compound | tag rows |
|---|--:|
| added_sugar | 777 |
| sodium | 578 |
| rapid_carb | 547 |
| saturated_fat | 541 |
| milk_allergen | 453 |
| gluten_allergen | 361 |
| potassium | 240 |
| nut_allergen | 207 |
| soy_allergen | 158 |
| trans_fat | 90 |
| caffeine | 58 |
| tyramine | 47 |
| vitamin_k | 46 |
| sesame_allergen | 42 |
| calcium_mineral_chelation | 34 |
| mustard_allergen | 32 |
| egg_allergen | 26 |
| histamine | 24 |
| oxalate | 8 |
| sulphite_allergen | 6 |
| fish_allergen | 5 |
| crustacean_shellfish_allergen | 4 |
| alcohol | 3 |
| purine | 2 |
| licorice_glycyrrhizin | 1 |

## 3. Top 20 ingredients still untagged (add these to `ingredient_aliases.csv`)

915 distinct tokens remain unresolved after both passes (mostly single-occurrence). The 20 most common:

| # | ingredient (cleaned) | occurrences | example food |
|--:|---|--:|---|
| 1 | firm white pumpkin | 1 | Petha |
| 2 | kitchen lime | 1 | Petha |
| 3 | alum powder | 1 | Petha |
| 4 | molu leaf | 1 | Singori |
| 5 | coconut flakes | 1 | Cham cham |
| 6 | elachi | 1 | Adhirasam |
| 7 | loaf bread | 1 | Double ka meetha |
| 8 | black lentils | 1 | Kuzhi paniyaram |
| 9 | mung bean | 1 | Mysore pak |
| 10 | khus-khus seeds | 1 | Anarsa |
| 11 | potol | 1 | Maach Jhol |
| 12 | boiled pork | 1 | Pork Bharta |
| 13 | axone | 1 | Galho |
| 14 | pork | 1 | Galho |
| 15 | shimla mirch | 1 | Aloo shimla mirch |
| 16 | ladies finger | 1 | Bhindi masala |
| 17 | chicken thighs | 1 | Biryani |
| 18 | naan bread | 1 | Chicken Tikka masala |
| 19 | tomato sauce | 1 | Chicken Tikka masala |
| 20 | skinless chicken breasts | 1 | Chicken Tikka masala |

Every token that occurred **>=2 times** was consumed by the LLM fallback pass (either given a tag or explicitly reviewed as benign), so the residue here is all single-occurrence - mostly home-recipe wording in `indian_food.csv` (`ladies finger`, `shimla mirch`, `naan bread`, `axone`, `pork`). Worth aliasing by hand: `naan bread`/`loaf bread` -> gluten_allergen+rapid_carb, `tomato sauce` -> sodium, `black lentils`/`mung bean` -> benign.

### LLM-assigned food tags to spot-check

166 distinct tokens were given a risk tag by the LLM pass (method=llm). The ones touching the most foods:

| ingredient token | risk_compounds (LLM) | foods affected | rationale |
|---|---|--:|---|
| edible vegetable oil | saturated_fat | 123 | unspecified 'vegetable oil' in Indian packaged food is frequently palm - low-confidence saturated_fat |
| acidity regulators | sodium | 109 | often sodium-based salts (citrate/bicarbonate) - low-confidence sodium |
| starch | rapid_carb | 43 | refined starch - rapidly digested |
| tomato | potassium | 33 | fresh tomato - modest potassium |
| chocolate | added_sugar;saturated_fat | 29 | chocolate/compound coating - sugar plus cocoa-butter/tropical fat; trace caffeine |
| baking powder | sodium | 27 | baking powder contains sodium bicarbonate |
| rice | rapid_carb | 25 | milled rice / rice product - medium-high glycaemic index |
| cocoa mass | caffeine | 22 | cocoa solids carry small amounts of caffeine/theobromine |
| edible vegetable fat | saturated_fat | 22 | solid/tropical/interesterified fat - high in saturated fatty acids |
| hydrolysed vegetable protein | sodium | 21 | HVP - manufactured with salt, high free glutamate; sodium load |
| lemon juice | added_sugar | 19 | single-strength fruit juice - free sugars with fibre removed |
| mustard oil | mustard_allergen | 16 | mustard oil - refined form is low-protein; flag low for mustard-allergic users |
| leavening agents | sodium | 16 | often sodium-based salts (citrate/bicarbonate) - low-confidence sodium |
| tomato powder | potassium | 16 | concentrated tomato - notable potassium |
| hydrogenated vegetable fat | saturated_fat;trans_fat | 15 | hydrogenated fat - saturated, possible residual trans fat |
| nuts | nut_allergen | 14 | 'nuts' plural / mixed-nut blend |
| mango pulp | added_sugar | 14 | fruit pulp/puree - intrinsic sugars, some fibre retained |
| fractionated fat | saturated_fat | 14 | solid/tropical/interesterified fat - high in saturated fatty acids |
| hydrolyzed vegetable protein | sodium | 13 | HVP - manufactured with salt, high free glutamate; sodium load |
| interesterified vegetable fat | saturated_fat | 12 | solid/tropical/interesterified fat - high in saturated fatty acids |

Full audit trail: `food_ingredient_method_log.csv` (filter `method == llm`).

## 4. Drug classification - method mix

`drug_classes.csv`: 293546 (medicine, active-ingredient) rows from 195,605 medicines; 1000 distinct active ingredients.

| method | (medicine, active) rows | share |
|---|--:|--:|
| lookup | 267811 | 91.2% |
| llm | 12360 | 4.2% |
| stem | 11557 | 3.9% |
| unmapped | 1070 | 0.4% |
| subcategory | 748 | 0.3% |

| method | distinct active ingredients | share |
|---|--:|--:|
| lookup | 541 | 54.1% |
| llm | 388 | 38.8% |
| stem | 46 | 4.6% |
| unmapped | 17 | 1.7% |
| subcategory | 8 | 0.8% |

- **99.6%** of (medicine, active) rows were classified; **17** distinct ingredients remain unmapped.

### Active ingredients still unmapped (add to `drug_class_lookup.csv`)

| active_ingredient | medicine_count | top sub_category |
|---|--:|---|
| bacitracin | 249 | Ophthalmological Anti Infectives Medicines |
| sulphadoxine | 204 | Other Anti Malarials |
| choline salicylate | 96 | Other Stomatologicals |
| benzydamine | 77 | Topical Anti Rheumatic Non Steroidal |
| diloxanide | 65 | Amebicides |
| amlexanox | 64 | All Other Anti Ulcerants |
| glycerin | 56 | Solutions For Osmotic Therapy |
| citric acid | 53 | All Other Urological Products |
| alpha ketoanalogue | 48 | Urinary Incontinence Products |
| sulphacetamide | 37 | Topical Antibiotics And Or Sulphonamids |
| clofazimine | 33 | Drugs For Treatment Of Lepra |
| aztreonam | 32 | Other Beta Lactam Antibacterials Excluding Penicillins Cephalosporins |
| human | 24 | Pure Vaccines |
| enclomiphene | 17 | Gonadotrophins Including Other Ovulation Stimulants |
| stavudine | 8 | Hiv Antivirals |
| sodium aminosalicylate | 4 | Systemic Sulphonamides Excluding Trimethoprim Combinations |
| live freeze dried lactic acid bacteria and bifidobacteria | 3 | Intestinal Anti Inflammatory Agents |

These are mostly comma-split fragments of multi-word names (`human`, `recombinant`, `oral)`, `w-135)`, `and 18) vaccine`) - fix by making the salt-composition splitter paren-aware, not by adding aliases.

## 5. Draft interaction rules (STEP 5 - NOT VALIDATED)

`interaction_rules.csv`: **129 candidate rows**, every one flagged `review_status = NEEDS CLINICAL REVIEW`.

- Severity mix: MODERATE 67, HIGH 49, LOW 13
- 119 rules reference a drug_class that appears in this medicine dataset; 10 are forward-looking (`drug_class_present_in_dataset = no`) because the dataset has almost no cardiology drugs - no warfarin, digoxin, loop diuretics, spironolactone, non-dihydropyridine CCBs, pioglitazone, clonidine.

> This table was seeded from well-known food-drug interaction patterns as a
> starting point. It has **not** been checked by a pharmacist or clinician.
> Do not surface it in the app or treat any row as authoritative until it has
> been reviewed, and expect rows to be edited, downgraded, or removed.

## 6. Known limitations / follow-ups

- **Nutrient columns unused.** `packaged_foods_india.csv` has real `Sodium_mg`, `Sugar_g`, `Saturated_Fat_g` etc.; tagging currently keys off the ingredient text only. A numeric threshold pass would make `sodium` / `added_sugar` / `saturated_fat` tags quantitative and catch items whose ingredient list is vague.
- **`edible vegetable oil`** (123 mentions) is tagged `saturated_fat` at low confidence 0.4 - in Indian packaged food it is usually palm, but confirm.
- **`lecithin`** is assumed soy-derived (common in India) and tagged `soy_allergen` 0.7 - sunflower lecithin exists; review.
- **Coconut** is deliberately NOT tagged `nut_allergen` (low clinical cross-reactivity); revisit per user allergy profile.
- **Allergen tags are ingredient-derived only** - 'may contain' / shared-line cross-contamination statements are not parsed.
- **salt_composition splitter** is not parenthesis-aware, so a few vaccine / combination names split on internal commas into fragments (see section 4).
- **sub_category** in `medicine_data.csv` often describes the combination product, not the molecule (e.g. amitriptyline filed under 'Other Anti Malarials'); it is used only as a last-resort, low-trust class signal.
