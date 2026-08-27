"""
Step 4 - LLM fallback classification of active ingredients that
drug_class_lookup.csv + stem rules + sub_category whitelist could not resolve.

The "LLM" is Claude (this session) applying pharmacology knowledge. Every row is
method=llm with a rationale for spot-checking. Writes llm_drug_classes.csv, then
re-run 04_drug_classes.py.

Ingredients not covered here are left unmapped on purpose so step 6 surfaces
them for manual lookup curation.
"""
import csv, os
HERE = os.path.dirname(os.path.abspath(__file__))
UNMAP = os.path.join(HERE, "unmapped_active_ingredients.csv")
OUT   = os.path.join(HERE, "llm_drug_classes.csv")

M = {}
def add(cls, names, conf=0.9, why=""):
    for n in names:
        M[n.strip().lower()] = (cls, conf, why or f"pharmacology knowledge: {cls}")

# ---- salt-form / ester variants of already-known molecules
add("Beta blocker", ["metoprolol succinate", "metoprolol tartrate", "nebivolol hydrochloride"])
add("Angiotensin receptor blocker (ARB)", ["olmesartan medoxomil", "candesartan cilexetil"])
add("ACE inhibitor", ["perindopril erbumine", "perindopril arginine", "enalapril maleate",
                       "ramipril "])
add("Progestogen", ["medroxyprogesterone acetate", "megestrol", "megestrol acetate",
                     "dienogest", "hydroxyprogesterone caproate", "gestodene"])
add("Proton pump inhibitor", ["esomeprazole magnesium", "esomeprazole strontium"])
add("Corticosteroid", ["loteprednol etabonate", "fluorometholone", "fluocinolone acetonide",
                        "difluprednate", "prednisolone acetate", "prednisolone sodium phosphate",
                        "triamcinolone acetonide", "budesonide "])
add("Polymyxin", ["colistin sulphate", "colistimethate sodium", "colistin"])
add("Iron supplement", ["iron sucrose", "iron isomaltoside", "sodium feredetate",
                         "iron", "ferric hydroxide", "ferric pyrophosphate",
                         "iron dextran", "ferrous glycine sulphate"])
add("Kinase inhibitor", ["imatinib mesylate", "sorafenib", "sorafenib tosylate",
                          "pazopanib", "nintedanib", "regorafenib", "gefitinib",
                          "erlotinib", "lapatinib", "sunitinib", "dasatinib",
                          "nilotinib", "ruxolitinib", "cabozantinib"])
add("Typical antipsychotic", ["haloperidol decanoate", "flupentixol decanoate",
                               "zuclopenthixol decanoate", "melitracen "])
add("Antiviral (anti-influenza)", ["oseltamivir phosphate"])
add("Insulin", ["insulin isophane/nph", "human insulin/soluble insulin",
                "insulin lispro protamine", "insulin aspart protamine", "human premix",
                "insulin glargine ", "biphasic isophane insulin (nph)", "isophane insulin nph"])

# ---- vitamins & cofactors
add("Vitamin B3 (niacin)", ["niacinamide", "nicotinamide", "vitamin b3", "niacin "])
add("Vitamin B5 (pantothenic acid)", ["d-panthenol", "dexpanthenol", "pantothenic acid",
                                       "calcium pantothenate"])
add("Vitamin B7 (biotin)", ["biotin"])
add("Vitamin B9 (folate)", ["l-methyl folate", "l-methylfolate", "levomefolate calcium",
                             "calcium folinate", "folinic acid"])
add("Vitamin B6", ["pyridoxal-5-phosphate", "pyridoxal-5-phasphate", "pyridoxal phosphate"])
add("Vitamin B2 (riboflavin)", ["riboflavin", "vitamin b2", "riboflavine"])
add("Vitamin B12", ["mecobalamin "])
add("B-complex (multi)", ["vitamin b", "b complex", "vitamin b complex"])
add("Vitamin E", ["tocoferol", "tocopherol", "tocopheryl acetate", "d-alpha tocopherol"])
add("Vitamin K", ["menadione sodium bisulfite", "menadione sodium bisulphite"])
add("Vitamin D analogue", ["vitamin d", "calcifediol", "paricalcitol"])
add("Folinic acid rescue / detox agent", ["calcium leucovorin", "leucovorin", "levoleucovorin"])

# ---- minerals / electrolytes / IV fluids
add("Mineral / electrolyte supplement", [
    "magnesium", "magnesium citrate", "magnesium bisglycinate", "magnesium oxide",
    "magnesium hydroxide ", "magnesium carbonate", "magnesium sulphate ",
    "calcium", "calcium chloride", "tribasic calcium phosphate", "calcium phosphate ",
    "zinc gluconate", "zinc oxide", "zinc sulphate monohydrate", "zinc chloride",
    "zinc acetate ", "chromium", "chromium chloride", "chromium picolinate",
    "copper", "copper sulphate", "manganese", "manganese sulphate", "selenious acid",
    "selenium ", "sodium fluoride", "stannous fluoride", "sodium acid phosphate",
    "sodium lactate", "potassium magnesium citrate ", "luvistin", "sodium chloride ",
    "potassium chloride "])
add("Antacid", ["magnesium trisilicate", "aluminium magnesium hydroxide"])
add("Mucosal protectant", ["zinc carnosine", "polaprezinc"])
add("IV fluid / parenteral nutrition", [
    "dextrose", "glucose ", "invert sugar", "glycine", "xylitol", "sorbitol solution",
    "ringer's lactate", "saline", "adapting electrolyte solutions", "low dextrans",
    "mannitol "])
add("Plasma volume expander", ["albumin", "dextran 40", "dextran", "hydroxyethyl starch",
                               "hetastarch", "gelatin polysuccinate"])
add("Osmotic diuretic", ["mannitol"])

# ---- cytotoxic chemotherapy
add("Cytotoxic chemotherapy", [
    "paclitaxel", "docetaxel", "cabazitaxel", "doxorubicin", "epirubicin",
    "daunorubicin", "idarubicin", "mitoxantrone", "mitomycin", "bleomycin",
    "dactinomycin", "cyclophosphamide", "ifosfamide", "chlorambucil", "melphalan",
    "bendamustine", "lomustine", "carmustine", "temozolomide", "dacarbazine",
    "hydroxyurea", "capecitabine", "fluorouracil", "5-fluorouracil", "tegafur",
    "uracil", "mercaptopurine", "6-mercaptopurine", "thioguanine", "cytarabine",
    "gemcitabine", "pemetrexed", "etoposide", "vincristine", "vinblastine",
    "vinorelbine", "cisplatin", "carboplatin", "oxaliplatin", "irinotecan",
    "topotecan", "pegaspargase", "asparaginase", "trabectedin"])
add("Antineoplastic - hormonal", [
    "abiraterone acetate", "bicalutamide", "enzalutamide", "flutamide",
    "nilutamide", "fosfestrol", "diethylstilbestrol", "cyproterone",
    "cyproterone acetate", "goserelin acetate", "leuprolide", "leuprorelin",
    "triptorelin", "buserelin", "degarelix", "estramustine"])
add("Immunomodulatory imide (IMiD)", ["lenalidomide", "thalidomide", "pomalidomide"])
add("Recombinant urate oxidase", ["rasburicase"])
add("Uroprotectant (chemotherapy)", ["mesna"])
add("Cytoprotectant (chemotherapy)", ["amifostine"])

# ---- biologics / immunology
add("Vaccine", [
    "inactivated influenza vaccine", "tetanus toxoid", "diphtheria toxoid",
    "pertussis toxoid", "rabies vaccine", "hepatitis b vaccine", "hepatitis a vaccine",
    "freeze-dried live attenuated hepatitis a vaccine", "measles vaccine",
    "rubella vaccine", "mumps virus vaccine", "salmonella typhi vaccine",
    "purified vi polysaccharide typhoid vaccine",
    "vi capsular polysaccharide of salmonella typhi", "typhoid vaccine",
    "pneumococcal polysaccharide vaccine", "pneumococcal 13 valent conjugate vaccine",
    "haemophilus type b conjugate vaccine",
    "haemophilus influenzae type b capsular polysaccharide",
    "meningococcal vaccine (group a", "w-135)",
    "human papillomavirus quadrivalent (types 6", "and 18) vaccine",
    "human papillomavirus bivalent vaccine", "polio vaccine",
    "varicella vaccine attenuated", "varicella vaccine", "bacillus calmette-guerin strain",
    "rotavirus vaccine (live attenuated", "oral)",
    "inactivated japanese encephalitis virus protein", "yellow fever virus (live",
    "attenuated)", "recombinant"])
add("Immunoglobulin / antiserum", [
    "human normal immunoglobulin", "anti rh d immunoglobulin", "anti-rh d immunoglobulin",
    "human hepatitis b immunoglobulin", "human rabies immunoglobulin",
    "equine rabies immunoglobulin", "diphtheria immune globulin", "human gamma globulin",
    "human antitetanus immunoglobulin", "tetanus immunoglobulin", "snake venom antiserum",
    "clostridium botulinum type a toxin-haemagglutinin complex",
    "clostridium botulinum type a toxin-haemagglu", "homologous immunoglobulin",
    "diphtheria immune globulin "])
add("Interferon", ["interferon alpha 2b", "interferon alpha 2a", "interferon beta-1a",
                    "interferon beta-1b", "pegylated interferon alpha 2a",
                    "pegylated interferon alpha 2b", "peginterferon"])
add("Colony-stimulating factor", ["filgrastim", "pegfilgrastim", "sargramostim",
                                   "molgramostim", "lenograstim", "nartograstim",
                                   "granulocyte colony stimulating factor", "plerixafor"])
add("Immunostimulant", ["pidotimod", "thymosin alpha", "thymosin alpha 1",
                         "bacterial lysate", "bcg (immunotherapy)"])
add("Growth factor (topical/systemic)", [
    "recombinant human epidermal growth factor", "becaplermin", "recombinant human platelet derived growth factor"])
add("Botulinum toxin", ["onabotulinumtoxina", "abobotulinumtoxina", "incobotulinumtoxina",
                         "botulinum toxin type a"])
add("Thrombopoietin receptor agonist", ["eltrombopag", "romiplostim", "avatrombopag"])
add("Multiple sclerosis immunomodulator", ["dimethyl fumarate", "fingolimod",
                                            "teriflunomide", "glatiramer acetate"])

# ---- neuromuscular blockers & anaesthetics
add("Neuromuscular blocking agent", ["atracurium", "cisatracurium", "vecuronium",
    "rocuronium", "pancuronium", "succinyl choline chloride", "suxamethonium",
    "mivacurium"])
add("General anaesthetic", ["propofol", "ketamine", "etomidate", "thiopental sodium",
    "thiopentone", "isoflurane", "sevoflurane", "halothane", "desflurane",
    "nitrous oxide"])
add("Neuromuscular block reversal", ["sugammadex"])

# ---- reproductive / endocrine
add("Gonadotropin", ["human chorionic gonadotropin", "menotrophin", "urofollitropin",
    "recombinant follicle stimulating hormone", "recombinant human follicle stimulating hormone",
    "recombinant human chorionic gonadotropin", "follitropin alfa", "corifollitropin alfa",
    "recombinant follicle stimulating", "menotropins"])
add("GnRH agonist", ["gonadorelin"])
add("GnRH antagonist", ["cetrorelix", "ganirelix"])
add("Androgen", ["testosterone", "testosterone propionate", "testosterone undecanoate",
                  "mesterolone", "danazol", "dehydroepiandrosterone", "dhea"])
add("SERM / anti-osteoporotic", ["centchroman", "ormeloxifene"])
add("Tissue-selective estrogen (STEAR)", ["tibolone"])
add("Antiprogestogen", ["mifepristone"])
add("Uterotonic", ["oxytocin", "carboprost", "carboprost tromethamine", "ergometrine (uterotonic)"])
add("Prostaglandin (obstetric)", ["dinoprostone", "dinoprost", "gemeprost"])
add("Tocolytic", ["ritodrine", "isoxsuprine", "atosiban", "hexoprenaline"])
add("Dopamine agonist (prolactin inhibitor)", ["cabergoline", "bromocriptine",
                                                "quinagolide", "piribedil"])
add("Vasopressin analogue", ["desmopressin", "vasopressin", "terlipressin", "argipressin",
                              "felypressin"])
add("Vasopressin V2 receptor antagonist", ["tolvaptan", "conivaptan"])
add("Somatostatin analogue", ["octreotide acetate", "octreotide", "lanreotide"])
add("Calcitonin", ["calcitonin", "salmon calcitonin"])
add("Parathyroid hormone analogue", ["teriparatide", "abaloparatide"])
add("Anti-osteoporotic (other)", ["strontium ranelate", "denosumab (osteoporosis)"])
add("Calcimimetic", ["cinacalcet", "etelcalcetide"])
add("ACTH / corticotropin", ["corticotropin", "tetracosactide", "acth"])
add("Growth hormone", ["somatropin", "somatrem"])
add("Antihypoglycaemic hormone", ["glucagon"])

# ---- GI
add("5-HT4 receptor agonist (prokinetic)", ["tegaserod", "prucalopride", "mosapride",
                                             "cinitapride", "renzapride"])
add("Chloride channel activator (laxative)", ["lubiprostone"])
add("Guanylate cyclase-C agonist (laxative)", ["linaclotide", "plecanatide"])
add("Bulk-forming laxative", ["polycarbophil", "calcium polycarbophil", "methylcellulose (laxative)"])
add("Stool softener", ["docusate", "docusate sodium"])
add("Stimulant laxative", ["phenolphthalein", "sodium picosulphate"])
add("Probiotic", ["saccharomyces boulardii", "lactobacillus sporogenes", "bacillus clausii",
                   "lactic acid bacteria", "live freeze dried lactic acid bacteria and b",
                   "bifidobacterium", "lactobacillus"])
add("Bile salt / digestive", ["sodium tauroglycocholate", "sodium taurocholate",
                               "ox bile extract"])
add("Serine protease inhibitor", ["camostat", "camostat mesilate", "nafamostat"])
add("Prebiotic", ["fructo oligosaccharide", "fructooligosaccharide (rx)"])

# ---- haemostasis / blood
add("Haemostatic (topical/systemic)", ["hemocoagulase", "adrenochrome monosemicarbazone",
    "carbazochrome", "carbazochrome sodium sulphonate"])
add("Antifibrinolytic (proteinase inhibitor)", ["aprotinin"])
add("Bioflavonoid", ["citrus bioflavonoid", "rutin", "rutoside", "diosmin", "hesperidin",
                      "troxerutin"])
add("Heparin antagonist", ["protamine sulfate", "protamine"])
add("Clotting factor / haemostatic protein", ["fibrinogen", "thrombin",
    "factor viii", "factor ix", "human fibrin sealant"])
add("Pentosan (bladder GAG)", ["pentosan polysulfate sodium"])

# ---- antidotes / chelators
add("Cholinesterase reactivator", ["pralidoxime", "obidoxime"])
add("Benzodiazepine antagonist", ["flumazenil"])
add("Iron chelator", ["deferoxamine", "desferrioxamine", "deferasirox", "deferiprone"])
add("Alcohol deterrent (ALDH inhibitor)", ["disulfiram"])
add("Anti-craving agent (alcohol dependence)", ["acamprosate"])
add("Alcohol metabolism modifier", ["metadoxine"])
add("Smoking cessation aid", ["nicotine", "varenicline", "cytisine", "bupropion (smoking)"])
add("Opioid antagonist", ["naloxone (antidote)"])

# ---- respiratory
add("Antitussive", ["levodropropizine", "levocloperastine", "cloperastine",
    "benzonatate", "terpin hydrate", "terpin", "oxeladin", "pipazethate",
    "dropropizine", "codeine (antitussive)", "isoaminile"])
add("Expectorant", ["ammonium chloride", "potassium iodide (expectorant)",
                     "sodium citrate (expectorant)"])
add("Antiseptic lozenge", ["amylmetacresol", "dichlorobenzyl alcohol", "hexylresorcinol"])
add("PDE4 inhibitor", ["roflumilast", "apremilast (pde4)"])
add("Thromboxane A2 antagonist", ["seratrodast", "ramatroban"])
add("Antifibrotic", ["pirfenidone"])
add("Respiratory stimulant", ["doxapram"])
add("Beta-2 agonist (bronchodilator)", ["orciprenaline", "metaproterenol"])
add("Sympathomimetic (decongestant/anorectic)", ["phenylpropanolamine", "phenylephrine (oral)"])
add("Pulmonary surfactant", ["poractant alfa", "colfosceril palmitate", "beractant",
                              "calfactant"])

# ---- obesity / metabolic
add("Lipase inhibitor (anti-obesity)", ["orlistat", "cetilistat"])
add("Anorectic (withdrawn/controlled)", ["fenfluramine", "sibutramine", "lorcaserin"])
add("Aldose reductase inhibitor", ["epalrestat"])
add("Dual PPAR agonist", ["saroglitazar"])
add("Lipid-lowering (nicotinic acid derivative)", ["acipimox", "policosanol"])

# ---- CNS / neuro
add("Melatonergic hypnotic", ["melatonin", "ramelteon", "agomelatine (melatonergic)"])
add("Tricyclic antidepressant", ["melitracen", "melitracen hydrochloride"])
add("Sedative-hypnotic (chloral group)", ["triclofos", "triclofos sodium",
                                           "chloral hydrate"])
add("Cholinesterase inhibitor", ["pyridostigmine", "neostigmine", "physostigmine",
                                   "ambenonium", "edrophonium"])
add("Nootropic / neurotrophic", ["alpha glycerylphosphorylcholine", "choline alfoscerate",
    "cerebroprotein hydrolysate", "idebenone", "choline", "l-alpha glyceryl phosphorylcholine"])
add("Neurodegenerative disease agent", ["riluzole", "edaravone", "dalfampridine",
                                         "nusinersen", "riluzole "])
add("Dopamine agonist (anti-parkinson)", ["piribedil "])
add("Antispasmodic (anticholinergic/musculotropic)", ["papaverine", "hyoscyamine",
    "isopropamide", "pinaverium bromide", "otilonium bromide", "valethamate",
    "valethamate bromide", "caroverine", "isopropamide iodide", "prifinium bromide",
    "tiemonium methylsulphate", "fenpiverinium"])
add("Skeletal muscle relaxant", ["methocarbamol"])
add("Cholinomimetic (bladder/GI)", ["bethanechol", "carbachol (systemic)"])
add("Diuretic (mild, OTC)", ["pamabrom"])
add("Opioid analgesic", ["dextropropoxyphene", "ethylmorphine", "butorphanol",
                          "tramadol (nos)", "dihydrocodeine (analgesic)"])

# ---- ophthalmic
add("NSAID (ophthalmic)", ["nepafenac", "bromfenac", "flurbiprofen (ophthalmic)"])
add("Alpha-2 adrenergic agonist (antiglaucoma)", ["brimonidine", "apraclonidine"])
add("Cholinergic miotic", ["pilocarpine"])
add("Mydriatic / cycloplegic", ["tropicamide", "cyclopentolate", "homatropine",
                                  "phenylephrine (ophthalmic)"])
add("Ocular decongestant", ["tetrahydrozoline", "tetryzoline", "naphazoline (ocular)"])
add("Ophthalmic preservative / oxidant", ["oxychloro complex", "stabilized oxychloro",
    "oxychloro", "stabilised oxychloro complex", "sodium perborate"])
add("Ocular lubricant", ["hydroxypropylmethylcellulose", "hydroxypropyl methyl cellulose",
    "hydroxyethylcellulose", "propylene glycol", "polyethylene glycol (ophthalmic)",
    "glycerin (ophthalmic)"])
add("Anti-VEGF (ophthalmic)", ["pegaptanib", "ranibizumab", "aflibercept", "bevacizumab (ophthalmic)"])
add("Diagnostic dye", ["fluorescein", "fluorescein sodium", "indocyanine green",
                        "rose bengal", "lissamine green"])

# ---- derm / topical
add("Topical antifungal", ["tolnaftate", "amorolfine", "ciclopirox", "ciclopirox olamine",
                            "undecylenic acid"])
add("Antipsoriatic", ["dithranol", "anthralin", "calcipotriol", "calcipotriene", "acitretin",
                        "tacalcitol"])
add("Topical anti-acne", ["azelaic acid", "nadifloxacin (acne)"])
add("Immune response modifier (topical)", ["imiquimod", "resiquimod"])
add("Counterirritant / topical analgesic", ["camphor", "menthol", "turpentine oil",
    "methyl salicylate", "capsaicin", "benzyl nicotinate", "methyl nicotinate",
    "diclofenac (topical rubefacient)"])
add("Antiseptic / disinfectant", ["chlorhexidine gluconate", "chlorbutol", "chlorocresol",
    "paradichlorobenzene", "benzoxonium chloride", "cetalkonium chloride", "cetrimide",
    "cetylpyridinium chloride", "benzalkonium chloride", "triclosan", "hexachlorophene"])
add("Preservative / antimicrobial excipient", ["phenoxyethanol", "phenylethyl alcohol",
    "benzoic acid", "benzyl alcohol", "sodium benzoate (preservative)", "thiomersal",
    "chlorbutanol"])
add("Astringent", ["tannic acid", "tannin", "hamamelis", "alum"])
add("Rubefacient / peripheral vasodilator", ["benzyl nicotinate "])
add("Peripheral vasodilator", ["pentoxifylline", "naftidrofuryl", "buflomedil", "cilostazol",
                                "isoxsuprine (vasodilator)"])
add("Prostaglandin E1 (vasodilator)", ["alprostadil"])
add("Sclerosant", ["polidocanol", "sodium tetradecyl sulphate", "ethanolamine oleate"])
add("Tissue adhesive", ["n-butyl-2-cyanoacrylate", "n butyl 2 cyanoacrylate"])
add("Emollient / keratolytic", ["urea", "lactic acid", "salicylic acid (topical)",
                                 "propylene glycol (topical)"])

# ---- urology / misc
add("Urinary analgesic", ["phenazopyridine"])
add("Radiographic contrast medium", ["iohexol", "iopamidol", "iopromide", "diatrizoic acid",
    "meglumine diatrizoate", "sodium diatrizoate", "meglumine diatrizoate ",
    "ioversol", "iodixanol", "barium sulphate", "gadobutrol", "gadopentetic acid"])
add("Enzyme (spreading factor)", ["hyaluronidase"])
add("Amoebicide", ["dehydroemetine", "hydroxyquinolines", "clioquinol", "iodoquinol"])
add("SYSADOA (osteoarthritis)", ["glucosamine", "glucosamine sulfate potassium chloride",
    "glucosamine sulphate", "chondroitin", "chondroitin sulphate", "methyl sulfonyl methane",
    "methylsulfonylmethane", "msm", "hyaluronic acid", "collagen peptide", "oxaceprol",
    "univestin", "diacerein (sysadoa)"])
add("DMARD (small molecule)", ["iguratimod"])
add("Herbal / traditional extract", ["allium cepa", "placenta extracts", "placentrex",
    "liver extract", "liver fraction 2 derived from fresh liver 01", "evening primrose oil",
    "bacterial lysate "])
add("Antioxidant / cytoprotective", ["glutathione", "resveratrol", "l-glutathione reduced"])
add("Amino acid / nutritional", ["levo-carnitine", "l-carnitine", "levocarnitine",
    "l-alanyl-l-glutamine", "l-glutamate", "glycine (nutrition)", "l-leucine", "l-isoleucine",
    "l-histidine hydrochloride", "phenylalanine", "lysine", "ornithine", "l-ornithine",
    "myo-inositol", "d-chiro-inositol", "l-lysine", "arginine hydrochloride"])
add("Omega-3 fatty acid", ["docosahexaenoic acid", "dha", "eicosapentaenoic acid", "epa",
                            "omega 3 fatty acids", "fish oil"])
add("Antithyroid", ["propyl thiouracil", "propylthiouracil "])
add("Fluoroquinolone", ["garenoxacin", "prulifloxacin", "pefloxacin", "lomefloxacin",
                         "fleroxacin", "besifloxacin"])
add("Local anaesthetic", ["benzoxonium chloride (local)", "pramoxine", "pramocaine",
                           "cinchocaine", "dibucaine", "zinc chloride (astringent local)"])
add("Antiseptic (otic)", ["acetic acid", "boric acid (otic)"])
add("Radioprotective / detox", ["amifostine "])
add("Erythropoiesis-stimulating agent", ["recombinant human erythropoietin alfa",
    "darbepoetin alfa", "epoetin beta", "methoxy polyethylene glycol-epoetin beta"])
add("Antidiuretic hormone analogue", ["desmopressin acetate"])
add("Aldosterone synthesis / mineralocorticoid", ["fludrocortisone"])
add("Xanthine oxidase inhibitor", ["febuxostat "])
add("Prokinetic (dopamine D2 antagonist)", ["levosulpiride "])

# --------------------------------------------------------------------------- #
def norm(s):
    return s.strip().lower()

M = {norm(k): v for k, v in M.items() if norm(k)}

rows = list(csv.DictReader(open(UNMAP, encoding="utf-8")))
out, covered = [], 0
for r in rows:
    ing = r["active_ingredient"].strip().lower()
    if ing in M:
        cls, conf, why = M[ing]
        covered += 1
        out.append(dict(active_ingredient=ing, drug_class=cls, confidence=conf,
                        method="llm", rationale=why))

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["active_ingredient", "drug_class",
                                      "confidence", "method", "rationale"])
    w.writeheader()
    w.writerows(out)

print(f"unmapped ingredients in       : {len(rows)}")
print(f"llm_drug_classes.csv rows     : {len(out)}")
print(f"still unmapped after LLM pass  : {len(rows) - covered}")
print(f"wrote {OUT}")
