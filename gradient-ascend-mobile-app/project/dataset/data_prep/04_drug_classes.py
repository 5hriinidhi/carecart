"""
Step 4 - parse medicine_data.salt_composition into active ingredient(s) and map
each to a drug_class.

Resolution order per active ingredient:
  1. drug_class_lookup.csv          exact name match          -> method=lookup
  2. drug_class_stem_rules.csv      suffix/prefix/contains     -> method=stem
  3. subcategory_class_map (below)  safe sub_category whitelist -> method=subcategory
  4. llm_drug_classes.csv           reviewer/LLM fallback      -> method=llm
  5. (none)                                                    -> method=unmapped

Inputs:
  medicine_data.csv  - unzipped from medicine_data.csv.zip. This script unzips it
                       to a temp dir automatically if it is not found next to the zip.
Outputs:
  drug_classes.csv                 medicine_id, active_ingredient, drug_class, method (+ product_name, salt_composition)
  active_ingredient_classes.csv    distinct active_ingredient -> class, method, medicine_count, top_sub_category
  unmapped_active_ingredients.csv  ingredients still unmapped after all passes (for step 6 / manual curation)
"""
import csv, os, re, sys, zipfile, tempfile, collections

HERE = os.path.dirname(os.path.abspath(__file__))
DS   = os.path.normpath(os.path.join(HERE, ".."))

ZIP_PATH = os.path.join(DS, "medicine_data.csv.zip")
CANDIDATES = [
    os.path.join(DS, "medicine_data.csv"),
    os.path.join(tempfile.gettempdir(), "carecart_medicine_data.csv"),
    r"C:/Users/SHRINI~1/AppData/Local/Temp/claude/C--Users-Shrinidhi-CARECART/cdfbac33-fa39-4d57-b133-31a5d1dc08a4/scratchpad/medicine_data.csv",
]
LOOKUP_CSV     = os.path.join(HERE, "drug_class_lookup.csv")
STEM_CSV       = os.path.join(HERE, "drug_class_stem_rules.csv")
LLM_CSV        = os.path.join(HERE, "llm_drug_classes.csv")   # optional

OUT_MED   = os.path.join(HERE, "drug_classes.csv")
OUT_AI    = os.path.join(HERE, "active_ingredient_classes.csv")
OUT_UNMAP = os.path.join(HERE, "unmapped_active_ingredients.csv")


def find_medicine_csv():
    for p in CANDIDATES:
        if os.path.exists(p):
            return p
    if os.path.exists(ZIP_PATH):
        dest = os.path.join(tempfile.gettempdir(), "carecart_medicine_data.csv")
        print(f"unzipping {ZIP_PATH} -> {dest} ...")
        with zipfile.ZipFile(ZIP_PATH) as z:
            name = [n for n in z.namelist() if n.lower().endswith(".csv")][0]
            with z.open(name) as src, open(dest, "wb") as out:
                while chunk := src.read(1 << 20):
                    out.write(chunk)
        return dest
    sys.exit("medicine_data.csv not found and no zip to unzip")


SRC = find_medicine_csv()

# --------------------------------------------------------------------------- #
DOSE_RE  = re.compile(r"\([^)]*\)")
SPLIT_RE = re.compile(r"\s*\+\s*|\s*&\s*|\s*,\s*")

def actives(salt):
    if not isinstance(salt, str) or not salt.strip():
        return []
    out = []
    for part in SPLIT_RE.split(salt):
        name = DOSE_RE.sub("", part).strip().lower()
        name = re.sub(r"\s+", " ", name).strip(" -.;:/")
        name = re.sub(r"\b\d+\s*(mg|mcg|g|gm|ml|iu|%|units?|w/v|v/v|million)\b.*$", "", name).strip()
        if name and not name.isdigit() and len(name) > 1:
            out.append(name)
    return out


with open(LOOKUP_CSV, encoding="utf-8") as f:
    LOOKUP = {r["active_ingredient"].strip().lower(): r["drug_class"]
              for r in csv.DictReader(f)}

STEMS = []
with open(STEM_CSV, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        STEMS.append((r["pattern"].strip().lower(), r["position"].strip(), r["drug_class"]))

LLM = {}
if os.path.exists(LLM_CSV):
    with open(LLM_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            c = (r.get("drug_class") or "").strip()
            if c and c.lower() not in ("", "unknown", "none"):
                LLM[r["active_ingredient"].strip().lower()] = c

# small, deliberately conservative sub_category -> class whitelist.
# (many sub_category values in this dataset describe the combo product, not the
#  molecule, so only unambiguous ones are used, and only as a late fallback.)
SUBCAT_MAP = {
    "cephalosporins": "Cephalosporin",
    "broad spectrum penicillins": "Penicillin",
    "medium and narrow spectrum penicillins": "Penicillin",
    "macrolides and similar types": "Macrolide",
    "anti ulcerants acid pump inhibitors": "Proton pump inhibitor",
    "anti epileptics": "Antiepileptic",
    "atypical antipsychotics": "Atypical antipsychotic",
    "systemic antihistamines": "Antihistamine",
    "gastroprokinetics": "Prokinetic",
    "anti rheumatics non steroidal systemic": "NSAID",
    "non narcotics and anti pyretics": "Analgesic / antipyretic",
    "systemic corticosteroids plain": "Corticosteroid",
    "anthelmintics excluding schistosomicides": "Anthelmintic",
    "platelet aggregation inhibitors": "Antiplatelet",
    "ace inhibitors plain": "ACE inhibitor",
    "tetracyclines and combinations": "Tetracycline",
    "antitubercular products": "Antitubercular",
    "anti inflammatory enzymes": "Proteolytic / anti-inflammatory enzyme",
    "nootropics": "Nootropic / neurotrophic",
    "bisphosphonates": "Bisphosphonate",
    "hmg coa reductase inhibitors statins": "Statin (HMG-CoA reductase inhibitor)",
}


def classify(name, sub_category):
    if name in LOOKUP:
        return LOOKUP[name], "lookup"
    for pat, pos, cls in STEMS:
        if pos == "suffix" and name.endswith(pat):
            return cls, "stem"
        if pos == "prefix" and name.startswith(pat):
            return cls, "stem"
        if pos == "contains" and pat in name:
            return cls, "stem"
    if name in LLM:
        return LLM[name], "llm"
    sc = str(sub_category or "").strip().lower()
    if sc in SUBCAT_MAP:
        return SUBCAT_MAP[sc], "subcategory"
    return "", "unmapped"


def main():
    import pandas as pd
    ai_count   = collections.Counter()
    ai_class   = {}            # name -> (class, method)
    ai_topsub  = collections.Counter()
    method_ct  = collections.Counter()
    n_rows = n_ai_rows = 0

    with open(OUT_MED, "w", newline="", encoding="utf-8") as fmed:
        wmed = csv.writer(fmed)
        wmed.writerow(["medicine_id", "product_name", "salt_composition",
                       "active_ingredient", "drug_class", "method"])
        mid = 0
        for ch in pd.read_csv(SRC, usecols=["product_name", "salt_composition", "sub_category"],
                              chunksize=100_000, dtype=str):
            for pname, salt, sub in zip(ch["product_name"], ch["salt_composition"], ch["sub_category"]):
                mid += 1
                n_rows += 1
                medicine_id = f"MD-{mid:06d}"
                al = actives(salt)
                if not al:
                    wmed.writerow([medicine_id, pname, salt, "", "", "unmapped"])
                    method_ct["no_active_parsed"] += 1
                    continue
                for a in al:
                    cls, method = classify(a, sub)
                    wmed.writerow([medicine_id, pname, salt, a, cls, method])
                    n_ai_rows += 1
                    method_ct[method] += 1
                    ai_count[a] += 1
                    ai_topsub[(a, str(sub).strip())] += 1
                    if a not in ai_class:
                        ai_class[a] = (cls, method)

    best_sub = {}
    for (a, s), n in ai_topsub.items():
        if a not in best_sub or n > best_sub[a][1]:
            best_sub[a] = (s, n)

    with open(OUT_AI, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["active_ingredient", "medicine_count", "drug_class", "method", "top_sub_category"])
        for a, n in ai_count.most_common():
            cls, method = ai_class[a]
            w.writerow([a, n, cls, method, best_sub.get(a, ("", 0))[0]])

    with open(OUT_UNMAP, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["active_ingredient", "medicine_count", "top_sub_category"])
        for a, n in ai_count.most_common():
            if ai_class[a][1] == "unmapped":
                w.writerow([a, n, best_sub.get(a, ("", 0))[0]])

    dist_total = len(ai_count)
    dist_unmapped = sum(1 for a in ai_class if ai_class[a][1] == "unmapped")
    print(f"medicine rows                 : {n_rows}")
    print(f"(medicine, active) rows       : {n_ai_rows}")
    print(f"distinct active ingredients   : {dist_total}")
    print(f"  distinct still unmapped     : {dist_unmapped}")
    print(f"\nmethod breakdown over (medicine, active) rows:")
    for m, c in method_ct.most_common():
        print(f"  {m:20s} {c:8d}  ({100*c/max(n_ai_rows,1):.1f}%)")
    mapped = n_ai_rows - method_ct.get("unmapped", 0)
    print(f"\nmapped (medicine,active) rows : {mapped}/{n_ai_rows} ({100*mapped/max(n_ai_rows,1):.1f}%)")
    print(f"\nwrote:\n  {OUT_MED}\n  {OUT_AI}\n  {OUT_UNMAP}")
    if not LLM:
        print("\nNOTE: no llm_drug_classes.csv - LLM fallback skipped. "
              "Review unmapped_active_ingredients.csv, add llm_drug_classes.csv, re-run.")


if __name__ == "__main__":
    main()
