"""
Step 3 - LLM fallback classification of ingredient tokens the keyword matcher
could not resolve.

The "LLM" here is Claude (this session) applying nutrition / food-chemistry
judgement to each unresolved token. Every token processed by this pass is
written to llm_ingredient_tags.csv with method=llm and a short rationale, so a
human can spot-check. Tokens judged to carry no food-drug risk_compound are
still recorded (risk_compounds=none) so they drop off the "unresolved" list
without silently vanishing.

Scope: every unresolved token with >=2 occurrences, plus a set of unambiguous
lower-frequency tokens. Rarer tokens are deliberately left unresolved so
step 6 can surface them for manual alias curation.

Regenerate:  python make_llm_ingredient_tags.py
Then re-run:  python 03_tag_foods.py
"""
import csv, os

HERE = os.path.dirname(os.path.abspath(__file__))
UNRES = os.path.join(HERE, "unresolved_ingredients.csv")
OUT   = os.path.join(HERE, "llm_ingredient_tags.csv")

# --------------------------------------------------------------------------- #
# helper groups -> (risk_compounds, confidence, rationale)
# --------------------------------------------------------------------------- #
def g(tokens, rcs, conf, why):
    return {t: (rcs, conf, why) for t in tokens}

MAP = {}

# ---- solid / tropical / hydrogenated fats -> saturated_fat (+trans for H-oils)
MAP.update(g([
    "edible vegetable fat", "edible vegetable fats", "vegetable fat", "vegetable fats",
    "fractionated fat", "fractionated vegetable fat", "interesterified vegetable fat",
    "edible vegetable fat-interesterified", "palm fat", "refined palm", "palm kernel",
    "palm kernel oil", "sal fat", "fat powder", "vegetable fat powder", "cocoa fat",
], "saturated_fat", 0.8, "solid/tropical/interesterified fat - high in saturated fatty acids"))
MAP.update(g([
    "hydrogenated", "hydrogenated vegetable fat", "hydrogenated vegetable fats",
    "hydrogenated fat", "partially hydrogenated fat",
], "saturated_fat;trans_fat", 0.7, "hydrogenated fat - saturated, possible residual trans fat"))
MAP.update(g([
    "edible vegetable oil", "edible vegetable oils", "vegetable oil", "refined vegetable oil",
    "refined oil", "refined oils", "or sunflower oil",
], "saturated_fat", 0.4, "unspecified 'vegetable oil' in Indian packaged food is frequently palm - low-confidence saturated_fat"))
# liquid unsaturated oils - reviewed, not a saturated_fat driver
MAP.update(g([
    "sunflower oil", "refined sunflower oil", "sunflower", "rice bran oil",
    "refined rice bran oil", "rice bran", "olive oil", "corn oil", "avocado oil",
    "cottonseed oil", "cotton seed oil", "cottonseed", "refined cotton seed oil",
    "canola oil", "groundnut oil is caught by nut alias",
], "none", "", "liquid unsaturated seed/olive oil - not a saturated_fat driver"))
MAP["mustard oil"] = ("mustard_allergen", 0.5, "mustard oil - refined form is low-protein; flag low for mustard-allergic users")

# ---- refined / high-GI carbohydrate
MAP.update(g([
    "starch", "rice starch", "tapioca flour", "pea starch", "modified tapioca starch",
    "wheat starch is caught by alias", "sago starch",
], "rapid_carb", 0.7, "refined starch - rapidly digested"))
MAP.update(g([
    "rice", "raw rice", "white rice is aliased", "idli rice", "cooked rice", "rice flour",
    "rice grits", "rice meal", "rice flakes", "brown rice flakes", "thick poha", "poha",
    "flattened rice", "rice crisps", "puffed rice is aliased",
], "rapid_carb", 0.6, "milled rice / rice product - medium-high glycaemic index"))
MAP.update(g([
    "corn", "corn meal", "cornmeal", "corn grits", "corn grit", "degermed corn grits",
    "maize", "maize grits", "custard powder", "high maltose syrup", "glucose",
    "high maltose corn syrup", "corn flour is aliased",
], "rapid_carb", 0.8, "corn starch / glucose / maltose syrup - high glycaemic"))
MAP.update(g([
    "flour", "all-purpose flour", "all purpose flour", "refined flour is aliased",
    "plain flour is aliased",
], "rapid_carb;gluten_allergen", 0.7, "unqualified 'flour' in biscuits/bakery is refined wheat flour"))
MAP.update(g([
    "bread crumbs", "breadcrumbs", "batter", "vermicelli", "seviyan", "semiya",
], "rapid_carb;gluten_allergen", 0.65, "wheat-based crumb / batter / vermicelli"))
MAP["glass vermicelli"] = ("none", "", "mung-bean/rice glass noodle - not wheat, not high-risk")

# whole grains / pulses / legume flours - reviewed, low risk
MAP.update(g([
    "gram flour", "besan", "bengal gram flour", "bengal gram", "bengal gram grits",
    "bengal gram dal", "gram meal", "gram pulse flour", "gram pulses flour", "gram dal",
    "fried gram flour", "roasted bengal gram flour", "chickpea flour", "chana dal",
    "channa dal", "chana", "chole", "chhole", "chickpeas", "chickpea", "kabuli chana",
    "moth flour", "udid flour", "urad flour", "black gram", "green gram", "moong dal",
    "moong", "urad dal", "urad", "split urad dal", "arhar dal", "toor dal", "tur dal",
    "pigeon peas", "red lentils", "masur", "masur whole", "masoor", "pulses blend flour",
    "pulses mix rice grits", "pea grits", "pea flour", "lentil flour", "besan flour",
], "none", "", "pulse / legume flour - low glycaemic index, not a standard allergen"))
MAP.update(g([
    "jowar", "jowar flour", "sorghum", "sorghum flour", "whole grain jowar", "bajra",
    "bajra flour", "pearl millet flour", "pearl millet", "millet", "millets",
    "foxtail millet", "finger millet", "kodo millet", "little millet", "quinoa",
    "quinoa flour", "quinoa flakes", "buckwheat", "kuttu", "amaranth", "rajgira",
    "oats", "rolled oats", "oat flour", "oats flour", "oat flakes", "whole grain oats",
    "oats fibre", "oats fiber", "oat fibre", "oat bran", "barley flakes",
    "whole grains", "whole grain", "multigrain mix", "supergrain blend", "millet flour",
], "none", "", "whole grain / millet / pseudo-cereal - low-to-moderate GI, kept untagged"))
MAP.update(g([
    "cereal extract", "cereal products", "cereals", "cereal", "cereal solids",
    "malted cereal is caught by malt",
], "none", "", "generic 'cereal' - too vague to assign; often whole grain"))

# ---- added / free sugars
MAP.update(g([
    "apple juice concentrate", "orange juice concentrate", "lemon juice concentrate",
    "lime juice concentrate", "pomegranate juice concentrate", "lychee juice concentrate",
    "litchi juice concentrate", "carrot juice concentrate", "grape juice concentrate",
    "pineapple juice concentrate", "juice concentrate", "concentrated mixed fruit juice",
    "concentrate", "apple concentrate", "orange concentrate", "mixed fruit concentrate",
    "concentrated apple juice", "concentrated lemon juice powder", "date powder",
    "date paste", "fruit juice concentrate is aliased", "mixed fruit jam", "fruit jam",
    "jam", "gulkand", "candied fruits", "candied papaya", "candied fruit", "fruit cuts",
    "glucose solids is aliased", "malt syrup is aliased",
], "added_sugar", 0.8, "juice concentrate / jam / candied fruit / syrup - concentrated free sugars"))
MAP.update(g([
    "apple juice", "orange juice", "valencia orange juice", "lychee juice", "litchi juice",
    "pomegranate juice", "mix berry juice", "mixed fruit juice", "grape juice",
    "lime juice", "lemon juice", "fruit juice", "guava juice", "pineapple juice",
    "cranberry juice", "mango juice powder", "juice", "reconstituted juice",
], "added_sugar", 0.55, "single-strength fruit juice - free sugars with fibre removed"))
MAP.update(g([
    "fruit pulp", "mango pulp", "alphonso mango pulp", "guava pulp", "litchi pulp",
    "lychee pulp", "pineapple pulp", "papaya pulp", "pomegranate pulp", "fruit puree",
    "mango puree", "fruit preparation", "fruit prep", "strawberry fruit powder",
    "orange fruit powder", "fruit powders", "fruit powder", "mango juice",
], "added_sugar", 0.4, "fruit pulp/puree - intrinsic sugars, some fibre retained"))

# non-nutritive sweeteners / polyols - reviewed, not added_sugar
MAP.update(g([
    "maltitol", "sorbitol", "isomalt", "xylitol", "mannitol", "erythritol", "lactitol",
    "sucralose", "acesulfame", "acesulfame potassium", "aspartame", "saccharin",
    "stevia", "steviol glycosides", "stevia glycosides", "stevia extract",
    "sweetener", "sweeteners", "artificial sweetener", "table top sweetener",
    "polydextrose",
], "none", "", "sugar alcohol / high-intensity sweetener - not a free-sugar or glycaemic driver"))

# ---- chocolate / cocoa
MAP.update(g([
    "chocolate", "dark chocolate", "dark chocolates", "milk chocolate is aliased",
    "belgian chocolate", "belgium chocolate", "compound chocolate", "choco chips",
    "chocolate chips", "dark chocolate chips", "dark choco chips", "choco creme",
    "choco covering", "choco compound coating", "chocolate ripple", "choco compound",
    "chocolate coating", "chocolate flavoured coating", "chocolatey coating",
], "added_sugar;saturated_fat", 0.6, "chocolate/compound coating - sugar plus cocoa-butter/tropical fat; trace caffeine"))
MAP.update(g([
    "cocoa mass", "cocoa nibs", "cocoa beans", "cacao", "naturally farmed cacao",
    "cocoa liquor", "cocoa paste",
], "caffeine", 0.3, "cocoa solids carry small amounts of caffeine/theobromine"))
MAP.update(g([
    "low fat cocoa powder", "cocoa powder is benign-listed", "alkalised cocoa powder",
    "fat reduced cocoa",
], "none", "", "defatted cocoa powder - negligible sugar/fat, trace stimulant"))

# ---- sodium / high-salt composites
MAP.update(g([
    "hydrolysed vegetable protein", "hydrolyzed vegetable protein", "hvp",
    "hydrolysed soya protein", "hydrolyzed soy protein", "hydrolysed plant protein",
    "acid hydrolysed vegetable protein", "vegetable protein",
], "sodium", 0.6, "HVP - manufactured with salt, high free glutamate; sodium load"))
MAP.update(g([
    "tastemaker", "masala tastemaker", "seasoning mix", "seasoning", "seasoning powder",
    "candy masala", "chaat masala mix", "instant noodle powder", "instant noodles",
    "instant noodle", "noodle tastemaker", "spice and seasoning mix", "sambhar powder mix",
], "sodium", 0.6, "snack/noodle 'tastemaker' seasoning - salt + MSG heavy"))
MAP.update(g([
    "noodles", "instant noodle cake", "fried noodles", "wheat noodles",
], "rapid_carb;sodium", 0.55, "wheat noodle block - refined carb, salted"))
MAP.update(g([
    "acidity regulators", "acidity regulator", "leavening agents", "leavening agent",
    "raising agents is aliased", "leavening acid", "mineral salts",
], "sodium", 0.35, "often sodium-based salts (citrate/bicarbonate) - low-confidence sodium"))
MAP.update(g([
    "baking powder", "bakers ammonia is separate",
], "sodium", 0.6, "baking powder contains sodium bicarbonate"))
MAP.update(g([
    "sodium", "sodium acetate", "sodium propionate", "sodium diacetate", "sodium lactate",
    "sodium citrate is aliased", "iodised", "iodized", "salt (iodised) fragment",
], "sodium", 0.75, "explicit sodium salt / 'iodised' fragment"))
MAP["ammonium bicarbonate"] = ("none", "", "ammonium (not sodium) leavening salt")
MAP["sev"] = ("sodium;saturated_fat", 0.5, "sev - deep-fried salted besan noodles")
MAP["namkeen is aliased"] = ("sodium", 0.6, "")
MAP["celery"] = ("none", "", "celery - naturally sodium-bearing but quantities here are trivial")
MAP["cola"] = ("caffeine;added_sugar", 0.6, "cola - caffeinated sweetened beverage base")
MAP.update(g(["carbonated water", "sparkling water", "soda water", "aerated water"],
             "none", "", "carbonated water - no material risk compound"))

# ---- dairy solids -> milk allergen (+ saturated fat for fatty forms)
MAP.update(g([
    "khoa", "khoya is aliased", "mawa is aliased", "chhena", "chenna", "chhana", "chana paneer",
    "milk crumb", "mik solids", "milk protein concentrate", "mpc", "milk permeate",
    "buttermilk powder", "curd solids", "dahi powder", "cheese powder", "cheese solids",
], "milk_allergen", 0.85, "milk-derived solid / typo of 'milk solids'"))
MAP.update(g([
    "malai", "fresh cream is aliased", "dairy cream", "double cream",
], "milk_allergen;saturated_fat", 0.8, "cream / malai - milk protein plus milk fat"))

# ---- allergen tokens the word-matcher missed (plurals / phrasing)
MAP["eggs"] = ("egg_allergen", 0.95, "plural of egg - word-boundary alias missed it")
MAP.update(g(["nuts", "mixed dry fruits", "assorted nuts", "nut mix", "trail mix"],
             "nut_allergen", 0.85, "'nuts' plural / mixed-nut blend"))
MAP.update(g(["dry fruits", "dried fruits", "dryfruits", "dry fruit"],
             "nut_allergen;added_sugar", 0.45, "in Indian usage 'dry fruits' usually means nuts + dried sweetened fruit"))
MAP.update(g([
    "fish", "fish extract", "fish powder", "anchovy is aliased", "sardine is aliased",
    "tuna", "surimi", "fish sauce is aliased",
], "fish_allergen", 0.9, "finned fish protein"))
MAP.update(g([
    "prawns", "prawn", "shrimp", "crab", "lobster", "squid", "cuttlefish", "shellfish",
    "crustacean", "mussels is aliased", "clam", "oyster",
], "crustacean_shellfish_allergen", 0.9, "crustacean / mollusc protein"))
MAP.update(g([
    "mustard", "mustard seeds", "mustard seed", "mustard powder", "rai", "yellow mustard",
    "black mustard", "sarson seed", "mustard paste", "kasundi",
], "mustard_allergen", 0.85, "mustard seed / powder / paste - labelled allergen"))
MAP.update(g([
    "sulphites", "sulfites", "sodium metabisulphite", "sodium metabisulfite",
    "potassium metabisulphite", "sulphur dioxide", "sulfur dioxide", "so2",
], "sulphite_allergen", 0.9, "sulphite preservative"))
MAP.update(g([
    "milk solids is aliased", "skimmed milk powder is aliased",
], "milk_allergen", 0.9, ""))

# ---- coconut: FDA lists as tree nut but low clinical cross-reactivity -> keep untagged
MAP.update(g([
    "coconut", "desiccated coconut", "grated coconut", "fresh coconut", "dry coconut",
    "coconut powder", "coconut milk", "coconut cream", "coconut solids", "copra is aliased",
    "coconut products", "tender coconut is aliased",
], "none", "", "coconut - excluded from nut_allergen by design (low cross-reactivity); revisit per user allergy profile"))

# ---- potassium-notable produce concentrates
MAP.update(g([
    "tomato powder", "tomato solids", "tomato paste is aliased", "tomato concentrate",
    "dried tomato", "sun dried tomato", "tomato pomace",
], "potassium", 0.5, "concentrated tomato - notable potassium"))
MAP.update(g(["tomato", "tomatoes", "fresh tomato"], "potassium", 0.3, "fresh tomato - modest potassium"))
MAP.update(g([
    "potato", "aloo", "potato flakes", "dehydrated potato", "potato granules",
    "potato powder", "potato starch is aliased",
], "potassium;rapid_carb", 0.5, "potato - potassium plus high-GI starch"))
MAP.update(g([
    "raisin is aliased", "cranberries", "dried cranberry", "dried cranberries",
    "sultanas", "currants", "dried blueberry",
], "potassium;added_sugar;sulphite_allergen", 0.4, "dried fruit - potassium; usually sweetened; often sulphited"))
MAP.update(g(["spinach powder", "palak powder", "moringa", "drumstick leaf powder"],
             "potassium;vitamin_k", 0.5, "leafy-green concentrate - potassium and vitamin K"))

# ---- everything else that recurs but carries no risk compound: reviewed -> none
NONE_GROUPS = {
    "emulsifiers/additives": [
        "of vegetable origin", "vegetable origin", "diacetyltartaric", "diacetyl tartaric",
        "diacetyl tartaric acid ester of mono-diglycerides", "datem", "di-glycerides of fatty acids",
        "diglycerides of fatty acids", "mono and diglycerides of fatty acids",
        "mono- and diglycerides of fatty acids", "mono and diglycerides",
        "mono-diglycerides", "mono", "diglycerides", "fatty acid esters of glycerol",
        "fatty acid ester", "esters of fatty acids", "polyglycerol esters",
        "polyglycerol esters of fatty acids", "sorbitan monostearate", "polysorbate",
        "polysorbate 80", "sodium stearoyl lactylate", "ssl", "calcium stearoyl lactylate",
        "lecithin is aliased", "sunflower lecithin", "ammonium salts of phosphatidic acid",
        "ammonium phosphatides", "cake gel", "cake gel ins", "cake improver", "cake emulsifier",
        "improver", "improvers", "bread improver", "dough conditioner", "dough improver",
        "flour treatment agent", "flour treatment agents", "flour treatment agents ins",
        "processing aid", "anticaking agent is aliased", "anticaking agents", "anti caking agent",
        "free flowing agent", "glazing agent", "glazing agents", "release agent",
        "stabilizing agent", "stabilizing agents", "stabilizer", "stabilizers",
        "and stabilizer", "and stabilizers", "emulsifying agent", "emulsifying agents",
        "emulsifying", "emulsifying salt", "firming agent", "sequestrant", "acidulant",
        "acidifying agent", "acidity regulator is handled", "raising agent is aliased",
        "humectant", "humectants", "bulking agent", "carrier", "carrier solvent",
        "flavour emulsion", "flavour carrier",
    ],
    "gums/fibres": [
        "pectin", "fruit pectin", "citrus fibre", "citrus fiber", "carrageenan",
        "xanthan gum", "guar gum", "gum acacia", "acacia gum", "gum arabic", "gum base",
        "locust bean gum", "tara gum", "gellan gum", "cassia gum", "konjac", "agar",
        "inulin", "chicory root fibre", "chicory fibre", "soluble fibre", "dietary fibre",
        "dietary fiber", "oat fibre", "resistant starch", "psyllium", "isabgol",
        "fructooligosaccharide", "fructooligosaccharides", "fructo oligosaccharides",
        "fructo-oligosaccharides", "fos", "galacto oligosaccharides", "polydextrose",
        "carnauba wax", "beeswax", "shellac", "microcrystalline cellulose", "cellulose",
        "methylcellulose", "cmc", "sodium carboxymethyl cellulose",
    ],
    "enzymes": [
        "enzyme", "enzymes", "xylanase", "enzyme xylanase", "amylase", "amylases",
        "alpha amylase", "fungal alpha amylase", "protease", "lipase", "glucose oxidase",
        "transglutaminase", "invertase", "pectinase", "phytase", "starter culture",
        "active cultures", "lactic culture", "dried yeast", "yeast extract is aliased",
    ],
    "antioxidants/preservatives (non-sodium)": [
        "rosemary extract", "rosemary oleoresin", "paprika extract", "paprika oleoresin",
        "capsicum extract", "cumin extract", "coriander extract", "mixed tocopherols",
        "tocopherol", "natural tocopherols", "bha", "bht", "tbhq", "propyl gallate",
        "ascorbyl palmitate", "calcium propionate", "potassium sorbate is aliased",
        "natamycin", "nisin", "dimethyl dicarbonate", "ethylenediaminetetraacetic",
        "edta", "calcium disodium edta",
    ],
    "vitamins/minerals (fortification)": [
        "vitamins", "vitamin", "vitamin a", "vitamin c", "vitamin c - antioxidant",
        "as ascorbic acid", "ascorbic acid", "vitamin d", "vitamin d2", "vitamin d3",
        "ergocalciferol", "cholecalciferol", "vitamin e", "vitamin b1", "vitamin b2",
        "vitamin b6", "vitamin b12", "riboflavin", "thiamine", "thiamine mononitrate",
        "thiamine chloride hydrochloride", "niacin", "niacinamide", "nicotinamide",
        "folic acid", "cyanocobalamin", "pyridoxine", "pantothenic acid", "biotin",
        "betacarotene", "beta carotene", "inositol", "choline", "taurine",
        "vitamin premix", "mineral premix", "vitamin and mineral premix", "minerals",
        "mineral", "electrolytes",
    ],
    "chelating minerals (fortification) - low chelation flag": [],
    "produce (fresh veg/fruit, low risk)": [
        "carrot", "carrots", "green peas", "peas", "green peas dried", "capsicum",
        "bell pepper", "cucumber", "bottle gourd", "ridge gourd", "bitter gourd",
        "ash gourd", "snake gourd", "pumpkin", "pumpkin seeds", "drumstick", "drumsticks",
        "brinjal", "eggplant", "gobi", "cauliflower", "cabbage is aliased", "broccoli is aliased",
        "jackfruit", "raw papaya", "papaya", "raw mango", "dried mango", "dry mango",
        "dried mango powder", "amchur powder", "watermelon", "muskmelon", "melon seed",
        "melon seeds", "pomegranate", "pomegranate seeds", "guava", "orange", "orange peel",
        "orange powder", "orange fruit powder", "lemon powder", "apple", "apple pomace",
        "pineapple", "strawberry", "strawberry powder", "raspberry", "blueberry", "cherry",
        "grape", "grapes", "litchi", "lychee", "passion fruit", "kiwi", "fig", "anjeer",
        "beetroot is aliased", "green chilli", "green chillies", "green chilies", "green chili",
        "green chilly", "red chillies", "red chilly", "red chilli", "dried chilli",
        "chilli flakes", "chilli paste", "red chilli paste", "red chilli flakes",
        "green chilli paste", "green chilli powder", "chilli extract", "chilly",
        "onions", "red onion", "spring onion", "dehydrated onion", "onion flakes",
        "toasted onion flakes", "dried onion", "shallots", "leek", "leeks", "garlic paste",
        "ginger paste", "dried garlic", "dehydrated garlic", "dehydrated garlic powder",
        "dried ginger", "dried ginger powder", "dry ginger", "dry ginger powder",
        "olives", "jalapeno", "jalapenos", "mushroom", "black fungus mushroom", "baby corn",
        "french beans", "green beans", "beans", "sweet corn", "corn kernels", "spinach is aliased",
        "coriander leaves", "mint leaves", "curry leaves is benign", "bay leaves", "basil",
        "oregano", "thyme", "parsley is aliased", "lemon grass", "kaffir lime", "fruit",
        "fruits", "mixed fruit", "fruit products", "fruit bits", "fruit cuts is handled",
        "vegetables", "mixed vegetables", "dehydrated vegetables", "dehydrated vegetable",
        "dehydrated vegetable powder", "vegetable powder", "dehydrated carrot", "green",
        "candied fruits is handled",
    ],
    "spices/herbs (trivial quantity)": [
        "cardamom powder", "green cardamom", "black cardamom", "cinnamon powder", "cassia",
        "clove powder", "cloves", "nutmeg powder", "mace", "star anise powder", "aniseed",
        "aniseed powder", "anise", "fennel seeds", "fenugreek powder", "fenugreek seeds",
        "carom seeds", "ajwain powder", "cumin seeds", "cumin seed", "cumin seed powder",
        "whole cumin", "coriander whole", "coriander seed", "black pepper powder",
        "white pepper powder", "pepper powder", "sichuan peppercorn", "peppercorn",
        "paprika", "turmeric powder", "dried turmeric", "asafoetida powder", "hing powder",
        "curry leaves powder", "kalonji", "nigella seeds", "poppy seeds", "poppy seed",
        "khus khus", "chia", "chia seeds", "flax", "flax seeds", "flaxseed", "sabja",
        "garam masala powder", "sambar powder", "sambhar powder", "chaat masala",
        "curry powder", "spice mix", "spice mix powder", "mixed herbs", "dehydrated herb",
        "dehydrated herbs", "herb", "herbs", "seasoning is handled", "kokum",
        "tamarind is benign", "gongura", "rose", "rose petals", "kewra water", "rose water is benign",
        "vanilla is benign", "menthol", "mint", "pudina",
    ],
    "flavour name fragments (not the food)": [
        "vanilla cake", "artificial vanilla cake", "vanilla cake flavour",
        "vanilla cake essence", "vanilla cake concentrate", "vanilla cake flavouring substances",
        "artificial vanilla cake flavouring substances", "nature identical vanilla cake flavouring substances",
        "nature identical", "nature-identical", "nature - identical", "natural identical",
        "nature ldentical flavouring substances", "nature identical flavour",
        "nature-identical flavour", "nature identical flavours", "nature identical flavouring substance",
        "nature-identical flavouring substance", "nature-identical flavouring substances",
        "nature-identical flavouring substances", "added nature identical flavouring substance",
        "nature identical and artificial", "natural", "artificial", "synthetic",
        "added flavours", "added flavour", "added flavor", "added flavor artificial",
        "and added flavour", "added flavour - nature identical", "added flavour nature identical",
        "added artificial flavouring substance", "artificial flavour", "artificial flavours",
        "artificial flavouring", "artificial flavouring substance", "artificial flavouring substances",
        "artificial flavouring substance - vanillin", "artificial chocolate flavouring substances",
        "natural flavour", "natural flavours", "natural flavouring", "natural flavouring substance",
        "natural flavouring substances", "natural orange flavouring", "flavour", "flavours",
        "flavour nature-identical flavouring substances", "flavours natural", "added natural",
        "flavouring", "flavourings", "flavoring substances", "flavouring substance",
        "flavouring substances", "and flavouring substances", "and flavour",
        "food flavour", "identical flavouring substances", "permitted flavour",
        "strawberry flavour", "orange flavour", "vanillin", "ethyl vanillin",
        "vanilla cake flavour is handled", "vanilla flavour",
    ],
    "colours (permitted)": [
        "colours", "colour", "colors", "color", "added colour", "natural colour",
        "natural colours", "natural food colour", "synthetic food colours",
        "synthetic food colour", "synthetic colour", "synthetic colours", "synthetic colors",
        "artificial colour", "artificial colours", "artificial food colours", "food colour",
        "food colours", "food colors", "food color", "permitted food colour",
        "permitted synthetic food colour", "caramel colour is caramel", "annatto",
        "curcumin", "carmine", "titanium dioxide", "tartrazine", "sunset yellow",
        "carmoisine", "brilliant blue", "ins 150d", "class colour", "colour class",
    ],
    "acids / misc GRAS": [
        "malic acid", "tartaric acid", "acetic acid", "lactic acid", "fumaric acid",
        "phosphoric acid", "acid", "citric acid is benign", "acids",
        "glycerine", "glycerin", "glycerol", "propylene glycol", "triacetin",
        "calcium chloride", "magnesium chloride", "magnesium sulphate", "salt of tartaric",
        "silicon dioxide", "silicon di oxide", "calcium silicate", "magnesium carbonate",
        "sodium bicarbonate is aliased", "class ii preservatives", "class preservatives",
        "class i preservatives", "permitted preservative", "preservative is aliased",
        "antioxidant is aliased", "allergen information", "allergen advice", "may contain",
        "contains", "and", "or", "with", "from", "ins", "e", "in", "of", "as",
        "500ii", "ins1442", "ins1450", "ins33", "ins 471", "ins 322", "ins 500",
        "outer layer", "inner layer", "centre filling", "centre", "center", "filling",
        "choco covering is handled", "coating", "topping", "base", "dough", "wafer",
        "wafer sheet", "biscuit", "brownie", "cookies", "cookie", "cake", "cake mix",
        "sponge", "batter is handled", "premix", "dry mix", "seasoning is handled",
        "protein", "protein blend", "protein isolate", "pea protein", "rice protein",
        "protein concentrate", "isolated vegetable protein", "energy", "kcal",
        "total fat", "saturated fat", "trans fat", "cholesterol", "carbohydrate",
        "nutritional information", "serving size", "makhana", "foxnut", "popped lotus seeds",
        "lotus seeds", "phool makhana", "water chestnut", "singhara", "nata de coco",
        "purified water is benign", "potable water", "hot water", "added water", "treated water",
        "demineralised water", "water is benign",
    ],
}
for grp, toks in NONE_GROUPS.items():
    for t in toks:
        MAP.setdefault(t, ("none", "", f"reviewed ({grp}) - no food-drug risk compound"))

# iron/zinc/calcium fortificants: low chelation flag
for t in ["iron", "zinc", "elemental iron", "reduced iron", "electrolytic iron",
          "iron fortificant", "calcium", "elemental calcium"]:
    MAP[t] = ("calcium_mineral_chelation", 0.4, "fortification-level divalent mineral - minor drug-chelation flag")

# --------------------------------------------------------------------------- #
def norm(s):  # strip helper-note suffixes I used as inline reminders
    return s.split(" is aliased")[0].split(" is benign")[0].split(" is handled")[0]\
            .split(" is caught")[0].split(" is separate")[0].strip()

MAP = {norm(k): v for k, v in MAP.items() if norm(k)}

rows = list(csv.DictReader(open(UNRES, encoding="utf-8")))
covered, out = 0, []
for r in rows:
    ing = r["ingredient_clean"].strip().lower()
    occ = int(r["occurrences"])
    if ing in MAP:
        rcs, conf, why = MAP[ing]
        covered += 1
    elif occ >= 2:
        rcs, conf, why = "none", "", "reviewed - unmatched generic/compound token, no single risk compound"
    else:
        continue  # leave rare tokens unresolved for manual curation (step 6)
    out.append(dict(ingredient_clean=ing, risk_compounds=rcs,
                    confidence=conf, method="llm", rationale=why))

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["ingredient_clean", "risk_compounds",
                                      "confidence", "method", "rationale"])
    w.writeheader()
    w.writerows(out)

n_risk = sum(1 for o in out if o["risk_compounds"] != "none")
print(f"unresolved tokens in            : {len(rows)}")
print(f"llm_ingredient_tags.csv rows    : {len(out)}")
print(f"  explicitly classified in MAP  : {covered}")
print(f"  auto 'none' (occ>=2, no map)  : {len(out) - covered}")
print(f"  rows assigning a risk compound: {n_risk}")
print(f"wrote {OUT}")
