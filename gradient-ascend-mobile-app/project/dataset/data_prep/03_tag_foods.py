"""
Step 3 - tag food rows with risk_compounds.

Rule-based keyword/alias matcher first (ingredient_aliases.csv), LLM fallback
second (llm_ingredient_tags.csv, produced by a human/Claude review pass over
unresolved_ingredients.csv).

Run once with no llm_ingredient_tags.csv present -> produces unresolved_ingredients.csv.
A reviewer classifies those, saves llm_ingredient_tags.csv, then re-runs this.

Outputs:
  food_risk_tags.csv              food_id, risk_compound, confidence, method
  food_ingredient_method_log.csv  per-ingredient audit trail (spot-check the LLM rows here)
  unresolved_ingredients.csv      ingredient_clean, occurrences, example_food_id, example_food_name
"""
import csv, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
DS = os.path.normpath(os.path.join(HERE, ".."))

RISK_COMPOUNDS_CSV = os.path.join(HERE, "risk_compounds.csv")
ALIASES_CSV        = os.path.join(HERE, "ingredient_aliases.csv")
LLM_TAGS_CSV       = os.path.join(HERE, "llm_ingredient_tags.csv")   # optional

INDIAN_FOOD_CSV    = os.path.join(DS, "indian_food.csv")
PACKAGED_CSV       = os.path.join(DS, "packaged_foods_india.csv")

OUT_TAGS   = os.path.join(HERE, "food_risk_tags.csv")
OUT_LOG    = os.path.join(HERE, "food_ingredient_method_log.csv")
OUT_UNRES  = os.path.join(HERE, "unresolved_ingredients.csv")

# --------------------------------------------------------------------------- #
# load reference tables
# --------------------------------------------------------------------------- #
with open(RISK_COMPOUNDS_CSV, encoding="utf-8") as f:
    VALID_RC = {r["risk_compound"] for r in csv.DictReader(f)}

ALIASES = []  # (alias, risk_compound, match_type, confidence)
with open(ALIASES_CSV, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        rc = r["risk_compound"].strip()
        if rc not in VALID_RC:
            sys.exit(f"alias '{r['alias']}' -> unknown risk_compound '{rc}'")
        note = (r.get("notes") or "").lower()
        conf = 0.7 if ("low confidence" in note or "flag for review" in note
                       or "review" in note) else 0.9
        ALIASES.append((r["alias"].strip().lower(), rc, r["match_type"].strip(), conf))
# longer aliases first so "refined palm oil" wins the log line over "palm oil"
ALIASES.sort(key=lambda t: len(t[0]), reverse=True)

LLM_TAGS = {}       # ingredient_clean -> list[(risk_compound, confidence)]
LLM_REVIEWED = set()  # ingredient_clean seen in the LLM file (incl. reviewed-as-none)
if os.path.exists(LLM_TAGS_CSV):
    with open(LLM_TAGS_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ing = r["ingredient_clean"].strip().lower()
            LLM_REVIEWED.add(ing)
            rcs = [x.strip() for x in re.split(r"[;,|]", r["risk_compounds"]) if x.strip()]
            for rc in rcs:
                if rc in ("none", "benign", ""):
                    continue
                if rc not in VALID_RC:
                    sys.exit(f"llm tag for '{ing}' -> unknown risk_compound '{rc}'")
                try:
                    c = float(r.get("confidence", "") or 0.5)
                except ValueError:
                    c = 0.5
                LLM_TAGS.setdefault(ing, []).append((rc, c))

# --------------------------------------------------------------------------- #
# ingredient text parsing
# --------------------------------------------------------------------------- #
ADDITIVE_PREFIXES = [
    "artificial flavouring substances", "nature identical flavouring substances",
    "natural flavouring substances", "natural and artificial flavour",
    "natural & artificial flavour", "flavouring substances", "flavour enhancer",
    "flavor enhancer", "acidity regulator", "raising agent", "raising agents",
    "anticaking agent", "anti-caking agent", "anti caking agent", "emulsifying salt",
    "emulsifier", "emulsifiers", "stabiliser", "stabilizer", "stabilisers",
    "stabilizers", "preservative", "preservatives", "class ii preservative",
    "class i preservative", "antioxidant", "antioxidants", "humectant", "sequestrant",
    "thickener", "thickeners", "thickening agent", "gelling agent", "bulking agent",
    "glazing agent", "firming agent", "flour treatment agent", "added colour",
    "added color", "natural colour", "natural color", "synthetic food colour",
    "artificial colour", "food colour", "colour", "color", "permitted",
    "may contain", "contains", "ins", "e",
]
ENUM_RE  = re.compile(r"\b(?:ins|e)?\s*\d{3}[a-z]?(?:\s*\([ivx]+\))?\b", re.I)
PCT_RE   = re.compile(r"\d+(?:\.\d+)?\s*%")
NUM_RE   = re.compile(r"\b\d+(?:\.\d+)?\b")
ROMAN_RE = re.compile(r"\b[ivx]{1,4}\b", re.I)
WS_RE    = re.compile(r"\s+")

SPLIT_RE = re.compile(r"[,\(\)\[\]\{\}:;/]|\band\b|\bwith\b|\bfrom\b|&")

# genuinely benign / too-generic to send to the LLM or list as "untagged worth fixing"
BENIGN = {
    "water", "aqua", "air", "nitrogen", "carbon dioxide", "edible common salt",
    "common salt", "spices", "spice", "mixed spices", "spices and condiments",
    "condiments", "spice extract", "spice extracts", "seasoning", "herbs",
    "turmeric", "haldi", "chilli", "red chilli", "chilli powder", "coriander",
    "coriander powder", "cumin", "jeera", "mustard", "mustard seed", "curry leaf",
    "curry leaves", "asafoetida", "hing", "ginger", "garlic", "onion",
    "green chilli", "cardamom", "elaichi", "clove", "cinnamon", "dalchini",
    "bay leaf", "tej patta", "black pepper", "white pepper", "pepper", "saffron",
    "kesar", "nutmeg", "mace", "javitri", "fennel", "saunf", "carom", "ajwain",
    "fenugreek", "fenugreek seed", "kalonji", "nigella", "star anise", "anise",
    "tamarind", "imli", "kokum", "amchur", "dry mango powder", "mango powder",
    "rose water", "kewra", "vanilla", "vanillin", "yeast", "iodised salt",
    "iodized salt", "salt", "permitted class", "natural flavour", "natural flavours",
    "natural flavor", "flavour", "flavor", "flavours", "flavors", "colour", "color",
    "edible starch", "cocoa", "cocoa solids", "cocoa powder", "curry powder",
    "garam masala", "masala", "mint", "pudina", "lemon", "lime", "citric acid",
    "salt (iodised)",
}
# segment must NOT be tagged with these even though a substring alias fires
SPECIAL_SUPPRESS = [
    (re.compile(r"\bbean\b"), {"purine"}),          # 'kidney bean' -> not organ meat
    (re.compile(r"\bkidney bean\b"), {"purine"}),
    (re.compile(r"\bcoconut\b"), {"nut_allergen"}),
]
NEGATION_RE = re.compile(
    r"(sugar[-\s]?free|no added sugar|salt[-\s]?free|unsalted|no added salt|"
    r"fat[-\s]?free|gluten[-\s]?free|dairy[-\s]?free|milk[-\s]?free|"
    r"caffeine[-\s]?free|alcohol[-\s]?free|nut[-\s]?free|egg[-\s]?free)")
NEG_MAP = {
    "sugar": "added_sugar", "salt": "sodium", "fat": "saturated_fat",
    "gluten": "gluten_allergen", "dairy": "milk_allergen", "milk": "milk_allergen",
    "caffeine": "caffeine", "alcohol": "alcohol", "nut": "nut_allergen",
    "egg": "egg_allergen", "unsalted": "sodium",
}


def clean_segment(seg: str) -> str:
    s = seg.lower().strip()
    s = PCT_RE.sub(" ", s)
    s = ENUM_RE.sub(" ", s)
    s = s.replace(".", " ").replace("'", " ").replace('"', " ").replace("*", " ")
    s = NUM_RE.sub(" ", s)
    s = WS_RE.sub(" ", s).strip(" -–—_")
    for _ in range(3):
        for p in ADDITIVE_PREFIXES:
            if s == p or s.startswith(p + " "):
                s = s[len(p):].strip(" -–—_:")
                break
        else:
            break
    s = ROMAN_RE.sub(" ", s)
    s = WS_RE.sub(" ", s).strip(" -–—_")
    return s


def parse_ingredients(text: str):
    """Return list of (raw_segment, clean_name). Flattens parens/brackets."""
    if not text or str(text).strip().lower() in ("nan", "none", ""):
        return []
    raw = str(text).replace("\n", " ")
    segs = [x for x in SPLIT_RE.split(raw) if x and x.strip()]
    out, seen = [], set()
    for seg in segs:
        c = clean_segment(seg)
        if not c or len(c) < 2:
            continue
        key = c
        if key in seen:
            continue
        seen.add(key)
        out.append((seg.strip(), c))
    return out


def match_keyword(raw_seg: str, clean: str):
    """Return dict risk_compound -> confidence from alias table."""
    hay = " " + raw_seg.lower() + " | " + clean + " "
    hits = {}
    for alias, rc, mtype, conf in ALIASES:
        if mtype == "word":
            if re.search(r"\b" + re.escape(alias) + r"\b", hay):
                hits[rc] = max(hits.get(rc, 0), conf)
        else:
            if alias in hay:
                hits[rc] = max(hits.get(rc, 0), conf)
    # negation
    for m in NEGATION_RE.finditer(hay):
        token = m.group(1)
        for k, rc in NEG_MAP.items():
            if k in token:
                hits.pop(rc, None)
    # special suppressions
    for rx, drop in SPECIAL_SUPPRESS:
        if rx.search(hay):
            for rc in drop:
                hits.pop(rc, None)
    return hits


# --------------------------------------------------------------------------- #
# load food rows
# --------------------------------------------------------------------------- #
def load_foods():
    rows = []
    with open(INDIAN_FOOD_CSV, encoding="utf-8-sig") as f:
        for i, r in enumerate(csv.DictReader(f), 1):
            rows.append(dict(food_id=f"IF-{i:04d}", source_file="indian_food.csv",
                             name=r.get("name", "").strip(),
                             ingredients=r.get("ingredients", "")))
    with open(PACKAGED_CSV, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            sno = (r.get("S.No") or "").strip()
            rows.append(dict(food_id=f"PF-{sno}", source_file="packaged_foods_india.csv",
                             name=(r.get("Item name") or "").strip(),
                             ingredients=r.get("Ingredients", "")))
    return rows


def main():
    foods = load_foods()
    log_rows = []
    tag_acc = {}                       # (food_id, rc) -> [confidence, methods:set]
    unresolved = collections.Counter()
    unresolved_example = {}
    n_kw_ing = n_llm_ing = n_llm_benign_ing = n_unres_ing = n_total_ing = 0

    for fr in foods:
        for raw_seg, clean in parse_ingredients(fr["ingredients"]):
            n_total_ing += 1
            kw = match_keyword(raw_seg, clean)
            method = None
            rc_conf = {}
            if kw:
                method = "keyword"
                rc_conf = kw
                n_kw_ing += 1
            elif clean in LLM_TAGS:
                method = "llm"
                rc_conf = {rc: c for rc, c in LLM_TAGS[clean]}
                n_llm_ing += 1
            elif clean in LLM_REVIEWED:
                method = "benign(llm-reviewed)"
                n_llm_benign_ing += 1
            else:
                if clean not in BENIGN and re.search(r"[a-z]", clean) and len(clean) >= 3:
                    method = "unresolved"
                    n_unres_ing += 1
                    unresolved[clean] += 1
                    unresolved_example.setdefault(clean, (fr["food_id"], fr["name"]))
                else:
                    method = "benign"

            log_rows.append(dict(
                food_id=fr["food_id"], source_file=fr["source_file"],
                ingredient_raw=raw_seg, ingredient_clean=clean,
                risk_compounds=";".join(sorted(rc_conf)) or "", method=method))

            for rc, c in rc_conf.items():
                slot = tag_acc.setdefault((fr["food_id"], rc), [0.0, set()])
                slot[0] = max(slot[0], c)
                slot[1].add(method)

    # ----- write food_risk_tags.csv -----
    with open(OUT_TAGS, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["food_id", "risk_compound", "confidence", "method"])
        for (fid, rc), (conf, methods) in sorted(tag_acc.items()):
            m = "keyword" if "keyword" in methods else ("llm" if "llm" in methods else "|".join(sorted(methods)))
            w.writerow([fid, rc, round(conf, 2), m])

    # ----- write per-ingredient audit log -----
    with open(OUT_LOG, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["food_id", "source_file", "ingredient_raw",
                                          "ingredient_clean", "risk_compounds", "method"])
        w.writeheader()
        w.writerows(log_rows)

    # ----- write unresolved ingredients (sorted by frequency) -----
    with open(OUT_UNRES, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ingredient_clean", "occurrences", "example_food_id", "example_food_name"])
        for ing, cnt in unresolved.most_common():
            ex = unresolved_example[ing]
            w.writerow([ing, cnt, ex[0], ex[1]])

    tagged_ing = n_kw_ing + n_llm_ing
    print(f"foods processed              : {len(foods)}")
    print(f"ingredient mentions parsed   : {n_total_ing}")
    print(f"  tagged by keyword          : {n_kw_ing}")
    print(f"  tagged by LLM fallback     : {n_llm_ing}")
    print(f"  LLM-reviewed, no risk      : {n_llm_benign_ing}")
    print(f"  unresolved (need aliases)  : {n_unres_ing}")
    print(f"  treated as benign/generic  : {n_total_ing - tagged_ing - n_llm_benign_ing - n_unres_ing}")
    if tagged_ing:
        print(f"  keyword share of tagged    : {100*n_kw_ing/tagged_ing:.1f}%")
        print(f"  LLM share of tagged        : {100*n_llm_ing/tagged_ing:.1f}%")
    print(f"distinct unresolved tokens   : {len(unresolved)}")
    print(f"(food,risk_compound) tag rows: {len(tag_acc)}")
    print(f"\nwrote:\n  {OUT_TAGS}\n  {OUT_LOG}\n  {OUT_UNRES}")
    if not LLM_TAGS:
        print("\nNOTE: no llm_ingredient_tags.csv found - LLM fallback was skipped.")
        print("      Review unresolved_ingredients.csv, write llm_ingredient_tags.csv, re-run.")


if __name__ == "__main__":
    main()
