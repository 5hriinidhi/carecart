"""
Builds the two reviewable reference files used by 04_drug_classes.py:

  drug_class_stem_rules.csv   pattern, position, drug_class, example   (applied in order)
  drug_class_lookup.csv       active_ingredient, drug_class, source

Classes follow common clinical / ATC-flavoured groupings. Compiled from
standard pharmacology references (WHO ATC, BNF, Indian NLEM naming). This is a
seed - extend it; every entry is human-editable.
"""
import csv, os
HERE = os.path.dirname(os.path.abspath(__file__))

# ---- stem rules: (pattern, position in {suffix,prefix,contains}, drug_class, example)
# ORDER MATTERS - earlier rules win. Keep specific before generic.
STEM_RULES = [
    ("prazole",   "suffix",   "Proton pump inhibitor",              "omeprazole"),
    ("nidazole",  "suffix",   "Nitroimidazole antimicrobial",       "metronidazole"),
    ("conazole",  "suffix",   "Azole antifungal",                   "fluconazole"),
    ("imazole",   "suffix",   "Azole antifungal",                   "clotrimazole"),
    ("caftazidime_placeholder", "suffix", "", ""),
    ("floxacin",  "suffix",   "Fluoroquinolone",                    "ciprofloxacin"),
    ("cillin",    "suffix",   "Penicillin",                         "amoxycillin"),
    ("penem",     "suffix",   "Carbapenem",                         "meropenem"),
    ("cef",       "prefix",   "Cephalosporin",                      "cefixime"),
    ("ceph",      "prefix",   "Cephalosporin",                      "cephalexin"),
    ("cycline",   "suffix",   "Tetracycline",                       "doxycycline"),
    ("sartan",    "suffix",   "Angiotensin receptor blocker (ARB)", "telmisartan"),
    ("pril",      "suffix",   "ACE inhibitor",                      "ramipril"),
    ("dipine",    "suffix",   "Calcium channel blocker (dihydropyridine)", "amlodipine"),
    ("olol",      "suffix",   "Beta blocker",                       "atenolol"),
    ("alol",      "suffix",   "Beta blocker",                       "labetalol"),
    ("ilol",      "suffix",   "Beta blocker",                       "carvedilol"),
    ("statin",    "suffix",   "Statin (HMG-CoA reductase inhibitor)", "atorvastatin"),
    ("gliptin",   "suffix",   "DPP-4 inhibitor",                    "sitagliptin"),
    ("gliflozin", "suffix",   "SGLT2 inhibitor",                    "dapagliflozin"),
    ("glitazone", "suffix",   "Thiazolidinedione",                  "pioglitazone"),
    ("glinide",   "suffix",   "Meglitinide",                        "repaglinide"),
    ("parin",     "suffix",   "Heparin / low-molecular-weight heparin", "enoxaparin"),
    ("xaban",     "suffix",   "Direct oral anticoagulant (factor Xa inhibitor)", "apixaban"),
    ("gatran",    "suffix",   "Direct oral anticoagulant (thrombin inhibitor)", "dabigatran"),
    ("triptan",   "suffix",   "Triptan (5-HT1B/1D agonist)",        "sumatriptan"),
    ("setron",    "suffix",   "5-HT3 receptor antagonist",          "ondansetron"),
    ("afil",      "suffix",   "PDE5 inhibitor",                     "sildenafil"),
    ("dronic acid","suffix",  "Bisphosphonate",                     "zoledronic acid"),
    ("dronate",   "suffix",   "Bisphosphonate",                     "risedronate"),
    ("coxib",     "suffix",   "NSAID (COX-2 selective)",            "etoricoxib"),
    ("profen",    "suffix",   "NSAID",                              "ibuprofen"),
    ("caine",     "suffix",   "Local anaesthetic",                  "lignocaine"),
    ("azepam",    "suffix",   "Benzodiazepine",                     "diazepam"),
    ("zolam",     "suffix",   "Benzodiazepine",                     "alprazolam"),
    ("barbital",  "suffix",   "Barbiturate",                        "phenobarbital"),
    ("triptyline","suffix",   "Tricyclic antidepressant",           "amitriptyline"),
    ("pramine",   "suffix",   "Tricyclic antidepressant",           "imipramine"),
    ("oxetine",   "suffix",   "SSRI",                               "fluoxetine"),
    ("opram",     "suffix",   "SSRI",                               "citalopram"),
    ("faxine",    "suffix",   "SNRI",                               "venlafaxine"),
    ("azosin",    "suffix",   "Alpha-1 blocker",                    "prazosin"),
    ("osin",      "suffix",   "Alpha-1 blocker (uroselective)",     "tamsulosin"),
    ("terol",     "suffix",   "Beta-2 agonist (bronchodilator)",    "formoterol"),
    ("butamol",   "suffix",   "Beta-2 agonist (bronchodilator)",    "salbutamol"),
    ("tropium",   "suffix",   "Antimuscarinic bronchodilator",      "tiotropium"),
    ("lukast",    "suffix",   "Leukotriene receptor antagonist",    "montelukast"),
    ("phylline",  "suffix",   "Methylxanthine bronchodilator",      "theophylline"),
    ("pridone",   "suffix",   "Atypical antipsychotic",             "risperidone"),
    ("piperone_ph","suffix",  "", ""),
    ("apine",     "suffix",   "Atypical antipsychotic",             "olanzapine"),
    ("peridol",   "suffix",   "Typical antipsychotic (butyrophenone)", "haloperidol"),
    ("azine",     "suffix",   "Phenothiazine",                      "chlorpromazine"),
    ("tadine",    "suffix",   "Antihistamine (2nd generation)",     "loratadine"),
    ("tidine",    "suffix",   "H2 receptor antagonist",             "ranitidine"),
    ("azolam_ph", "suffix",   "", ""),
    ("gabalin",   "suffix",   "Gabapentinoid",                      "pregabalin"),
    ("gabapentin","suffix",   "Gabapentinoid",                      "gabapentin"),
    ("racetam",   "suffix",   "Racetam nootropic / antiepileptic",  "levetiracetam"),
    ("azepine",   "suffix",   "Carboxamide anticonvulsant",         "carbamazepine"),
    ("toin",      "suffix",   "Hydantoin anticonvulsant",           "phenytoin"),
    ("prost",     "suffix",   "Prostaglandin analogue",             "latanoprost"),
    ("sone",      "suffix",   "Corticosteroid",                     "prednisone"),
    ("solone",    "suffix",   "Corticosteroid",                     "prednisolone"),
    ("asone",     "suffix",   "Corticosteroid",                     "dexamethasone"),
    ("onide",     "suffix",   "Corticosteroid (topical/inhaled)",   "budesonide"),
    ("cort",      "suffix",   "Corticosteroid",                     "deflazacort"),
    ("vastatin_ph","suffix",  "", ""),
    ("tinib",     "suffix",   "Kinase inhibitor",                   "imatinib"),
    ("ciclib",    "suffix",   "CDK4/6 inhibitor",                   "palbociclib"),
    ("mab",       "suffix",   "Monoclonal antibody",               "adalimumab"),
    ("ximab_ph",  "suffix",   "", ""),
    ("navir",     "suffix",   "Antiretroviral (protease inhibitor)", "ritonavir"),
    ("tegravir",  "suffix",   "Antiretroviral (integrase inhibitor)", "dolutegravir"),
    ("ciclovir",  "suffix",   "Antiviral (nucleoside analogue)",    "acyclovir"),
    ("tinib_ph",  "suffix",   "", ""),
    ("vir",       "suffix",   "Antiviral",                          "favipiravir"),
    ("bendazole", "suffix",   "Anthelmintic (benzimidazole)",       "albendazole"),
    ("mectin",    "suffix",   "Anthelmintic (avermectin)",          "ivermectin"),
    ("quine",     "suffix",   "Antimalarial (aminoquinoline)",      "chloroquine"),
    ("arterol_ph","suffix",   "", ""),
]
STEM_RULES = [r for r in STEM_RULES if r[2]]  # drop placeholders

# ---- explicit ingredient -> class (name normalised lower-case, dose stripped)
LOOKUP = {}
def add(cls, names):
    for n in names:
        LOOKUP[n] = cls

add("Analgesic / antipyretic (aniline)", [
    "paracetamol", "acetaminophen", "paracetamol/acetaminophen"])
add("NSAID", [
    "diclofenac", "aceclofenac", "nimesulide", "mefenamic acid", "ibuprofen",
    "naproxen", "ketorolac", "ketoprofen", "flurbiprofen", "indomethacin",
    "piroxicam", "meloxicam", "lornoxicam", "etodolac", "aspirin",
    "acetylsalicylic acid", "diacerein", "nabumetone", "dexketoprofen"])
add("NSAID (COX-2 selective)", ["etoricoxib", "celecoxib", "parecoxib", "valdecoxib"])
add("Beta-lactamase inhibitor", [
    "clavulanic acid", "sulbactam", "tazobactum", "tazobactam", "avibactam"])
add("Penicillin", [
    "amoxycillin", "amoxicillin", "ampicillin", "cloxacillin", "dicloxacillin",
    "flucloxacillin", "piperacillin", "benzylpenicillin", "penicillin g",
    "penicillin v", "carbenicillin"])
add("Cephalosporin", [
    "cefixime", "cefpodoxime proxetil", "cefpodoxime", "cefuroxime", "cefalexin",
    "cephalexin", "cefadroxil", "ceftriaxone", "cefotaxime", "cefdinir",
    "cefaclor", "ceftazidime", "cefepime", "cefoperazone", "cefditoren",
    "ceftibuten", "cefprozil", " cefazolin", "cefazolin", "ceftaroline"])
add("Prokinetic (dopamine D2 antagonist)", [
    "domperidone", "metoclopramide", "levosulpiride", "itopride", "trimebutine"])
add("Biguanide (antidiabetic)", ["metformin"])
add("Sulfonylurea (antidiabetic)", [
    "glimepiride", "gliclazide", "glipizide", "glibenclamide", "glyburide",
    "gliquidone"])
add("DPP-4 inhibitor", ["teneligliptin", "sitagliptin", "vildagliptin",
                         "linagliptin", "saxagliptin", "alogliptin", "gemigliptin"])
add("SGLT2 inhibitor", ["dapagliflozin", "empagliflozin", "canagliflozin",
                         "remogliflozin etabonate", "remogliflozin", "ertugliflozin"])
add("Vitamin B12", ["methylcobalamin", "mecobalamin", "cyanocobalamin",
                     "hydroxocobalamin", "vitamin b12"])
add("Vitamin B6", ["pyridoxine", "vitamin b6"])
add("Vitamin B1", ["thiamine", "benfotiamine", "vitamin b1"])
add("Vitamin B9", ["folic acid", "folate", "l-methylfolate", "levomefolic acid"])
add("Vitamin D analogue", ["cholecalciferol", "calcitriol", "alfacalcidol",
                            "ergocalciferol", "vitamin d3", "vitamin d2", "calcifediol"])
add("Calcium supplement", ["calcium carbonate", "calcium citrate", "calcium lactate",
                            "calcium gluconate", "calcium phosphate", "coral calcium"])
add("Iron supplement", ["ferrous sulphate", "ferrous fumarate", "ferrous ascorbate",
                         "ferrous bisglycinate", "carbonyl iron", "iron polymaltose",
                         "ferric carboxymaltose", "ferrous gluconate",
                         "iron hydroxide polymaltose", "colloidal ferric hydroxide"])
add("Proteolytic / anti-inflammatory enzyme", [
    "serratiopeptidase", "serratepeptidase", "bromelain", "trypsin",
    "trypsin chymotrypsin", "chymotrypsin", "trypsin-chymotrypsin", "papain",
    "peptizyme", "rutoside", "trypsin  chymotrypsin"])
add("Skeletal muscle relaxant", [
    "chlorzoxazone", "thiocolchicoside", "baclofen", "tizanidine", "eperisone",
    "metaxalone", "cyclobenzaprine", "carisoprodol", "tolperisone", "quinine (cramps)"])
add("Antihistamine (1st generation)", [
    "chlorpheniramine maleate", "chlorpheniramine", "chlorphenamine",
    "diphenhydramine", "promethazine", "hydroxyzine", "cyproheptadine",
    "pheniramine", "pheniramine maleate", "dexchlorpheniramine", "triprolidine",
    "doxylamine", "dimenhydrinate", "meclizine", "buclizine", "clemastine"])
add("Antihistamine (2nd generation)", [
    "levocetirizine", "cetirizine", "fexofenadine", "loratadine", "desloratadine",
    "bilastine", "rupatadine", "ebastine", "bepotastine", "acrivastine",
    "levocetirizine dihydrochloride"])
add("Nasal / systemic decongestant (sympathomimetic)", [
    "phenylephrine", "pseudoephedrine", "oxymetazoline", "xylometazoline",
    "ephedrine", "naphazoline"])
add("Antitussive", ["dextromethorphan hydrobromide", "dextromethorphan",
                     "codeine phosphate", "noscapine", "pholcodine", "butamirate"])
add("Mucolytic / expectorant", ["ambroxol", "bromhexine", "acetylcysteine",
                                  "carbocisteine", "guaifenesin", "guaiphenesin",
                                  "erdosteine", "n-acetylcysteine"])
add("Leukotriene receptor antagonist", ["montelukast", "zafirlukast"])
add("Nitroimidazole antimicrobial", ["metronidazole", "ornidazole", "tinidazole",
                                       "secnidazole", "satranidazole", "nimorazole"])
add("Gabapentinoid", ["pregabalin", "gabapentin"])
add("SSRI", ["escitalopram oxalate", "escitalopram", "citalopram", "sertraline",
             "fluoxetine", "paroxetine", "fluvoxamine"])
add("SNRI", ["venlafaxine", "desvenlafaxine", "duloxetine", "milnacipran",
             "levomilnacipran"])
add("Tricyclic antidepressant", ["amitriptyline", "nortriptyline", "imipramine",
                                   "clomipramine", "dosulepin", "dothiepin",
                                   "trimipramine", "amoxapine"])
add("Atypical antidepressant", ["mirtazapine", "bupropion", "trazodone",
                                 "vortioxetine", "agomelatine", "tianeptine"])
add("Azole antifungal", ["itraconazole", "fluconazole", "ketoconazole",
                          "voriconazole", "clotrimazole", "miconazole",
                          "luliconazole", "sertaconazole", "eberconazole",
                          "posaconazole", "isavuconazole", "oxiconazole",
                          "butoconazole", "fenticonazole"])
add("Allylamine antifungal", ["terbinafine", "naftifine"])
add("Polyene antifungal", ["amphotericin b", "nystatin", "natamycin"])
add("Echinocandin antifungal", ["caspofungin", "micafungin", "anidulafungin"])
add("Proton pump inhibitor", ["rabeprazole", "pantoprazole", "omeprazole",
                               "esomeprazole", "lansoprazole", "dexlansoprazole",
                               "ilaprazole", "dexrabeprazole"])
add("H2 receptor antagonist", ["ranitidine", "famotidine", "cimetidine",
                                "nizatidine", "roxatidine"])
add("Antacid", ["aluminium hydroxide", "magnesium hydroxide", "milk of magnesia",
                "calcium carbonate + magnesium", "magaldrate", "hydrotalcite",
                "sodium bicarbonate", "aluminium hydroxide gel"])
add("Antiflatulent", ["simethicone", "simeticone", "dimethicone", "activated dimethicone"])
add("Mucosal protectant", ["sucralfate", "oxetacaine", "oxethazaine",
                            "bismuth subsalicylate", "rebamipide"])
add("Prostaglandin analogue (GI)", ["misoprostol"])
add("Aminosalicylate", ["mesalazine", "mesalamine", "sulfasalazine",
                         "balsalazide", "olsalazine", "5-asa"])
add("Macrolide", ["azithromycin", "clarithromycin", "erythromycin",
                   "roxithromycin", "spiramycin", "josamycin", "fidaxomicin"])
add("Lincosamide", ["clindamycin", "lincomycin"])
add("Aminoglycoside", ["gentamicin", "amikacin", "tobramycin", "neomycin",
                        "streptomycin", "netilmicin", "framycetin", "kanamycin",
                        "paromomycin"])
add("Glycopeptide", ["vancomycin", "teicoplanin"])
add("Oxazolidinone (weak MAO inhibitor)", ["linezolid", "tedizolid"])
add("Nitrofuran antibacterial", ["nitrofurantoin", "furazolidone"])
add("Fosfomycin", ["fosfomycin"])
add("Dihydrofolate reductase inhibitor", ["trimethoprim"])
add("Sulfonamide antibacterial", ["sulfamethoxazole", "sulphamethoxazole",
                                    "cotrimoxazole", "co-trimoxazole", "sulfadiazine"])
add("Carbapenem", ["meropenem", "imipenem", "ertapenem", "doripenem",
                    "imipenem + cilastatin", "faropenem"])
add("Penem (oral)", ["faropenem"])
add("Polymyxin", ["polymyxin b", "colistin", "colistimethate"])
add("Amphenicol", ["chloramphenicol", "quiniodochlor", "clioquinol"])
add("Tetracycline", ["doxycycline", "minocycline", "tetracycline", "tigecycline",
                      "demeclocycline"])
add("Rifamycin", ["rifampicin", "rifaximin", "rifabutin", "rifampin", "rifapentine"])
add("Antitubercular", ["isoniazid", "ethambutol", "pyrazinamide",
                        "para-aminosalicylic acid", "ethionamide", "cycloserine"])
add("Antiplatelet (P2Y12 inhibitor)", ["clopidogrel", "ticagrelor", "prasugrel",
                                        "ticlopidine"])
add("Anticoagulant (vitamin K antagonist)", ["warfarin", "acenocoumarol",
                                              "nicoumalone", "phenprocoumon"])
add("Direct oral anticoagulant", ["apixaban", "rivaroxaban", "dabigatran",
                                   "edoxaban", "dabigatran etexilate"])
add("Fibrinolytic", ["streptokinase", "urokinase", "alteplase", "tenecteplase",
                      "reteplase"])
add("Antifibrinolytic / haemostatic", ["tranexamic acid", "ethamsylate",
                                         "etamsylate", "aminocaproic acid"])
add("ACE inhibitor", ["ramipril", "enalapril", "lisinopril", "perindopril",
                       "captopril", "benazepril", "fosinopril", "trandolapril",
                       "imidapril", "quinapril"])
add("Angiotensin receptor blocker (ARB)", ["telmisartan", "losartan", "olmesartan",
                                            "valsartan", "irbesartan", "candesartan",
                                            "azilsartan"])
add("Calcium channel blocker (dihydropyridine)", ["amlodipine", "nifedipine",
    "felodipine", "cilnidipine", "nimodipine", "lercanidipine", "benidipine",
    "s-amlodipine", "clevidipine", "nitrendipine"])
add("Calcium channel blocker (non-dihydropyridine)", ["verapamil", "diltiazem"])
add("Calcium channel blocker (antivertigo/migraine)", ["flunarizine", "cinnarizine"])
add("Beta blocker", ["metoprolol", "atenolol", "propranolol", "bisoprolol",
                       "carvedilol", "nebivolol", "labetalol", "betaxolol",
                       "esmolol", "acebutolol"])
add("Statin (HMG-CoA reductase inhibitor)", ["atorvastatin", "rosuvastatin",
    "simvastatin", "pravastatin", "fluvastatin", "pitavastatin"])
add("Fibrate", ["fenofibrate", "gemfibrozil", "bezafibrate", "choline fenofibrate"])
add("Other lipid-lowering", ["ezetimibe", "bempedoic acid", "nicotinic acid",
                              "colesevelam", "cholestyramine"])
add("Loop diuretic", ["furosemide", "frusemide", "torsemide", "torasemide",
                       "bumetanide"])
add("Thiazide / thiazide-like diuretic", ["hydrochlorothiazide", "chlorthalidone",
    "indapamide", "metolazone", "chlorothiazide"])
add("Potassium-sparing diuretic / aldosterone antagonist", ["spironolactone",
    "eplerenone", "amiloride", "triamterene"])
add("Carbonic anhydrase inhibitor", ["acetazolamide", "dorzolamide", "brinzolamide"])
add("Cardiac glycoside", ["digoxin"])
add("Antiarrhythmic", ["amiodarone", "dronedarone", "flecainide", "propafenone",
                        "sotalol", "mexiletine", "ivabradine"])
add("Nitrate vasodilator", ["nitroglycerin", "glyceryl trinitrate",
    "isosorbide dinitrate", "isosorbide mononitrate", "nicorandil"])
add("Insulin", ["insulin", "insulin isophane", "insulin glargine", "insulin aspart",
                 "insulin lispro", "insulin degludec", "insulin detemir",
                 "regular insulin", "human insulin", "isophane insulin",
                 "insulin glulisine", "biphasic isophane insulin"])
add("GLP-1 receptor agonist", ["liraglutide", "dulaglutide", "semaglutide",
                                "exenatide"])
add("Alpha-glucosidase inhibitor", ["acarbose", "voglibose", "miglitol"])
add("Thiazolidinedione", ["pioglitazone", "rosiglitazone"])
add("Meglitinide", ["repaglinide", "nateglinide"])
add("Thyroid hormone", ["levothyroxine", "thyroxine", "l-thyroxine",
                         "liothyronine", "thyroid extract"])
add("Antithyroid", ["carbimazole", "methimazole", "propylthiouracil"])
add("Corticosteroid", ["prednisolone", "methylprednisolone", "prednisone",
    "dexamethasone", "betamethasone", "hydrocortisone", "triamcinolone",
    "deflazacort", "budesonide", "fluticasone", "fluticasone propionate",
    "fluticasone furoate", "mometasone", "beclometasone", "beclomethasone",
    "ciclesonide", "clobetasol", "clobetasone", "desonide", "fluocinolone",
    "halobetasol", "cortisone", "loteprednol", "difluprednate"])
add("Anabolic steroid", ["nandrolone decanoate", "nandrolone", "stanozolol",
                          "oxandrolone", "methandienone"])
add("Estrogen", ["estradiol", "ethinylestradiol", "ethinyl estradiol",
                  "conjugated estrogens", "estriol", "estradiol valerate"])
add("Progestogen", ["progesterone", "dydrogesterone", "norethisterone",
    "levonorgestrel", "drospirenone", "desogestrel", "medroxyprogesterone",
    "norgestrel", "gestodene", "nomegestrol", "allylestrenol", "hydroxyprogesterone"])
add("Selective estrogen receptor modulator", ["tamoxifen", "raloxifene",
                                               "ormeloxifene", "clomifene",
                                               "clomiphene", "bazedoxifene"])
add("Aromatase inhibitor", ["letrozole", "anastrozole", "exemestane"])
add("5-alpha reductase inhibitor", ["finasteride", "dutasteride"])
add("Alpha-1 blocker (uroselective)", ["tamsulosin", "alfuzosin", "silodosin"])
add("Alpha-1 blocker", ["prazosin", "terazosin", "doxazosin"])
add("Overactive bladder agent", ["oxybutynin", "solifenacin", "tolterodine",
                                  "darifenacin", "fesoterodine", "mirabegron",
                                  "trospium", "flavoxate"])
add("PDE5 inhibitor", ["sildenafil", "tadalafil", "vardenafil", "avanafil",
                        "udenafil"])
add("Benzodiazepine", ["clonazepam", "diazepam", "lorazepam", "alprazolam",
    "nitrazepam", "midazolam", "etizolam", "chlordiazepoxide", "clobazam",
    "oxazepam", "temazepam", "flurazepam", "clorazepate"])
add("Z-drug hypnotic", ["zolpidem", "zopiclone", "eszopiclone", "zaleplon"])
add("Barbiturate", ["phenobarbital", "phenobarbitone", "butalbital"])
add("Anxiolytic (azapirone)", ["buspirone"])
add("Antiepileptic", ["levetiracetam", "brivaracetam", "valproate", "valproic acid",
    "sodium valproate", "divalproex", "carbamazepine", "oxcarbazepine",
    "eslicarbazepine", "phenytoin", "fosphenytoin", "lamotrigine", "topiramate",
    "lacosamide", "vigabatrin", "zonisamide", "perampanel", "clobazam (adjunct)",
    "sultiame", "ethosuximide"])
add("Mood stabiliser", ["lithium", "lithium carbonate"])
add("Atypical antipsychotic", ["olanzapine", "quetiapine", "risperidone",
    "aripiprazole", "clozapine", "paliperidone", "ziprasidone", "lurasidone",
    "amisulpride", "asenapine", "cariprazine", "blonanserin", "brexpiprazole"])
add("Typical antipsychotic", ["haloperidol", "chlorpromazine", "trifluoperazine",
    "fluphenazine", "pimozide", "flupenthixol", "zuclopenthixol", "sulpiride",
    "levosulpiride (antipsychotic use)", "thioridazine", "loxapine",
    "penfluridol", "pipotiazine"])
add("Anticholinergic (anti-parkinson)", ["trihexyphenidyl", "benzhexol",
                                          "procyclidine", "biperiden"])
add("Dopaminergic anti-parkinson", ["levodopa", "carbidopa", "benserazide",
    "pramipexole", "ropinirole", "rotigotine", "amantadine", "rasagiline",
    "selegiline", "entacapone", "tolcapone", "safinamide"])
add("Cholinesterase inhibitor", ["donepezil", "rivastigmine", "galantamine"])
add("NMDA receptor antagonist", ["memantine"])
add("Nootropic / neurotrophic", ["piracetam", "citicoline", "cerebroprotein",
    "vinpocetine", "ginkgo biloba", "tricholine citrate"])
add("Triptan (5-HT1B/1D agonist)", ["sumatriptan", "rizatriptan", "naratriptan",
                                     "zolmitriptan", "eletriptan", "almotriptan",
                                     "frovatriptan"])
add("Ergot alkaloid", ["ergotamine", "dihydroergotamine", "methylergometrine",
                        "ergometrine", "methylergometrine maleate"])
add("5-HT3 receptor antagonist", ["ondansetron", "granisetron", "palonosetron",
                                   "ramosetron"])
add("Dopamine antagonist antiemetic", ["metoclopramide", "domperidone",
                                        "prochlorperapine", "prochlorperazine"])
add("NK1 receptor antagonist", ["aprepitant", "fosaprepitant", "netupitant"])
add("Antivertigo (histamine analogue)", ["betahistine"])
add("Antispasmodic (anticholinergic/musculotropic)", ["dicyclomine",
    "dicycloverine", "hyoscine", "hyoscine butylbromide", "drotaverine",
    "mebeverine", "pinaverium", "otilonium", "camylofin", "propantheline",
    "atropine", "clidinium"])
add("Antimotility agent", ["loperamide", "racecadotril", "diphenoxylate"])
add("Osmotic laxative", ["lactulose", "lactitol", "polyethylene glycol",
                          "macrogol", "sorbitol", "milk of magnesia (laxative)"])
add("Stimulant laxative", ["bisacodyl", "sodium picosulfate", "senna",
                            "sennosides", "castor oil"])
add("Bulk laxative", ["ispaghula", "psyllium", "isabgol", "sterculia"])
add("Bile acid", ["ursodeoxycholic acid", "ursodiol", "obeticholic acid",
                   "chenodeoxycholic acid"])
add("Hepatoprotective", ["silymarin", "silybin", "l-ornithine l-aspartate",
                          "lola", "ademetionine", "s-adenosylmethionine"])
add("Xanthine oxidase inhibitor", ["allopurinol", "febuxostat"])
add("Uricosuric", ["probenecid", "benzbromarone"])
add("Anti-gout (acute)", ["colchicine"])
add("Anthelmintic", ["albendazole", "mebendazole", "ivermectin",
                       "diethylcarbamazine", "praziquantel", "pyrantel pamoate",
                       "niclosamide", "levamisole"])
add("Antimalarial", ["hydroxychloroquine", "chloroquine", "artemether",
    "lumefantrine", "artesunate", "arterolane", "piperaquine", "primaquine",
    "mefloquine", "quinine", "sulfadoxine", "pyrimethamine", "atovaquone",
    "proguanil", "arteether", "alpha-beta arteether", "amodiaquine", "halofantrine"])
add("Antiviral (nucleoside analogue)", ["acyclovir", "valacyclovir", "aciclovir",
    "famciclovir", "ganciclovir", "valganciclovir", "ribavirin"])
add("Antiviral (anti-influenza)", ["oseltamivir", "zanamivir", "baloxavir"])
add("Antiviral (anti-hepatitis)", ["sofosbuvir", "ledipasvir", "daclatasvir",
                                     "velpatasvir", "entecavir", "tenofovir",
                                     "adefovir"])
add("Antiretroviral", ["lamivudine", "zidovudine", "abacavir", "emtricitabine",
    "efavirenz", "nevirapine", "dolutegravir", "raltegravir", "lopinavir",
    "ritonavir", "atazanavir", "darunavir", "tenofovir disoproxil fumarate",
    "tenofovir alafenamide"])
add("Local anaesthetic", ["lignocaine", "lidocaine", "bupivacaine", "ropivacaine",
    "prilocaine", "benzocaine", "tetracaine", "proparacaine", "chloroprocaine",
    "oxetacaine (local anaesthetic)"])
add("Opioid analgesic", ["tramadol", "codeine", "morphine", "fentanyl",
    "buprenorphine", "tapentadol", "oxycodone", "hydromorphone", "pethidine",
    "nalbuphine", "pentazocine", "tramadol hydrochloride", "dihydrocodeine",
    "methadone"])
add("Opioid antagonist", ["naloxone", "naltrexone", "nalmefene"])
add("Antispasmodic xanthine / smooth muscle", ["drotaverine hydrochloride"])
add("Methylxanthine bronchodilator", ["theophylline", "etophylline", "etofylline",
    "doxofylline", "acebrophylline", "aminophylline", "bamifylline"])
add("Beta-2 agonist (bronchodilator)", ["salbutamol", "levosalbutamol",
    "salmeterol", "formoterol", "indacaterol", "terbutaline", "bambuterol",
    "vilanterol", "olodaterol", "arformoterol"])
add("Antimuscarinic bronchodilator", ["ipratropium", "tiotropium",
    "glycopyrronium", "glycopyrrolate", "umeclidinium", "aclidinium"])
add("Mast cell stabiliser", ["sodium cromoglycate", "cromolyn", "ketotifen",
                              "nedocromil"])
add("Respiratory anti-inflammatory (non-steroidal)", ["fenspiride",
    "montelukast (respiratory)"])
add("Stimulant / wakefulness agent", ["caffeine", "modafinil", "armodafinil",
                                       "methylphenidate", "atomoxetine",
                                       "amphetamine", "dexamfetamine"])
add("Antidiarrhoeal (intestinal antiseptic)", ["quiniodochlor (antidiarrhoeal)"])
add("Antiseptic / disinfectant", ["povidone iodine", "chlorhexidine", "cetrimide",
    "hydrogen peroxide", "boric acid", "potassium permanganate", "silver sulfadiazine"])
add("Ocular lubricant", ["carboxymethylcellulose", "carboxymethyl cellulose",
    "hydroxypropyl methylcellulose", "hypromellose", "polyethylene glycol (ocular)",
    "sodium hyaluronate", "polyvinyl alcohol", "carbomer"])
add("Prostaglandin analogue (ophthalmic)", ["latanoprost", "bimatoprost",
                                             "travoprost", "tafluprost"])
add("Immunosuppressant (calcineurin / mTOR)", ["tacrolimus", "cyclosporine",
    "ciclosporin", "sirolimus", "everolimus", "pimecrolimus"])
add("Immunosuppressant / DMARD", ["methotrexate", "leflunomide", "azathioprine",
    "mycophenolate mofetil", "mycophenolate sodium", "mycophenolic acid",
    "sulfasalazine (DMARD)", "hydroxychloroquine (DMARD)", "apremilast",
    "tofacitinib", "baricitinib", "upadacitinib"])
add("Biologic DMARD (anti-TNF / interleukin)", ["adalimumab", "etanercept",
    "infliximab", "golimumab", "secukinumab", "ustekinumab", "rituximab",
    "tocilizumab"])
add("Bisphosphonate", ["alendronic acid", "alendronate", "risedronate",
    "zoledronic acid", "ibandronate", "pamidronate", "etidronate"])
add("Vitamin K", ["phytomenadione", "phylloquinone", "menadione", "vitamin k",
                   "vitamin k1", "menaquinone"])
add("Vitamin C", ["ascorbic acid", "vitamin c", "sodium ascorbate"])
add("Vitamin A", ["retinol", "vitamin a", "retinyl palmitate"])
add("Vitamin E", ["tocopherol", "alpha tocopherol", "vitamin e",
                   "tocopheryl acetate"])
add("Antioxidant / micronutrient", ["n-acetylcysteine (antioxidant)", "coenzyme q10",
    "ubidecarenone", "l-carnitine", "acetyl-l-carnitine", "alpha lipoic acid",
    "lycopene", "astaxanthin", "grape seed extract", "selenium", "zinc"])
add("Amino acid / nutritional", ["l-arginine", "arginine", "l-glutamine",
    "glutamine", "l-ornithine", "citrulline", "amino acids", "carnitine",
    "taurine", "creatine"])
add("Electrolyte / rehydration", ["oral rehydration salts", "ors",
    "sodium chloride", "potassium chloride", "sodium citrate",
    "zinc sulphate", "zinc acetate", "magnesium sulphate",
    "potassium magnesium citrate", "disodium hydrogen citrate",
    "potassium citrate", "sodium bicarbonate (systemic)"])
add("Laxative / appetite / misc GI", ["tricholine citrate (appetite)",
    "cyproheptadine (appetite)"])
add("Antiemetic (antihistamine)", ["doxylamine (antiemetic)",
    "meclizine (antiemetic)", "dimenhydrinate (antiemetic)"])
add("Digestive enzyme (pancreatic)", ["pancreatin", "pancrelipase",
    "fungal diastase", "alpha amylase (digestive)", "pepsin", "amylase",
    "lipase", "diastase", "papain (digestive)"])
add("Antidote / chelator", ["deferasirox", "deferiprone", "desferrioxamine",
    "penicillamine", "dimercaprol", "calcium disodium edetate"])
add("Antihistamine / antiemetic (phenothiazine)", ["promethazine (antiemetic)"])
add("H1 antihistamine (piperazine)", ["cinnarizine (antihistamine)"])
add("Antifungal (griseofulvin)", ["griseofulvin"])
add("Antiprotozoal (other)", ["nitazoxanide", "diloxanide furoate",
                                "sodium stibogluconate", "miltefosine"])
add("Expectorant (guaiacolate)", ["guaifenesin (expectorant)"])
add("Vasodilator (peripheral)", ["pentoxifylline", "cilostazol", "naftidrofuryl",
                                   "buflomedil"])
add("Antihypertensive (central alpha-2 agonist)", ["clonidine", "methyldopa",
                                                    "moxonidine"])
add("Antihypertensive (direct vasodilator)", ["hydralazine", "minoxidil"])
add("Pulmonary hypertension agent", ["bosentan", "ambrisentan", "macitentan",
                                      "riociguat"])
add("Phosphate binder", ["sevelamer", "lanthanum carbonate",
                          "calcium acetate (binder)"])
add("Potassium binder", ["calcium polystyrene sulphonate",
                          "sodium polystyrene sulphonate", "patiromer"])
add("Erythropoiesis-stimulating agent", ["erythropoietin", "epoetin alfa",
                                          "darbepoetin"])
add("Haematinic (other)", ["cobalt", "levo-folinate", "methylcobalamin (haematinic)"])
add("Antihistamine H1 (ocular)", ["olopatadine", "azelastine", "epinastine",
                                   "alcaftadine", "emedastine"])
add("Decongestant / antiallergic (ocular/nasal steroid)", ["mometasone furoate (nasal)",
    "fluticasone furoate (nasal)", "azelastine (nasal)"])
add("Topical retinoid", ["tretinoin", "adapalene", "isotretinoin", "tazarotene"])
add("Topical antibacterial (acne/skin)", ["clindamycin (topical)",
    "erythromycin (topical)", "nadifloxacin", "mupirocin", "fusidic acid",
    "framycetin (topical)", "sodium fusidate", "retapamulin", "ozenoxacin"])
add("Keratolytic", ["salicylic acid", "benzoyl peroxide", "urea (topical)",
                     "lactic acid (topical)", "coal tar", "podophyllotoxin"])
add("Antiscabietic / pediculicide", ["permethrin", "gamma benzene hexachloride",
    "lindane", "benzyl benzoate", "crotamiton"])
add("Emollient / barrier", ["liquid paraffin", "white soft paraffin",
    "dimethicone (topical)", "glycerin (topical)"])
add("Local haemorrhoid preparation", ["lignocaine + hydrocortisone",
    "tribenoside", "calcium dobesilate"])

with open(os.path.join(HERE, "drug_class_stem_rules.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["order", "pattern", "position", "drug_class", "example"])
    for i, (pat, pos, cls, ex) in enumerate(STEM_RULES, 1):
        w.writerow([i, pat, pos, cls, ex])

with open(os.path.join(HERE, "drug_class_lookup.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["active_ingredient", "drug_class", "source"])
    for name in sorted(LOOKUP):
        w.writerow([name, LOOKUP[name], "seed:pharmacology-reference"])

print(f"stem rules : {len(STEM_RULES)}")
print(f"lookup rows: {len(LOOKUP)}")
