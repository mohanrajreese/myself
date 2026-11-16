# 09 — Food Dataset Options (decision D3)

The PRD requires food search, categories and offline use (§5.4) but names no data source. Nutrition values are never invented: every catalogue value must come from a named dataset.

Licence notes below were checked on 16 November 2026. Anything marked **unconfirmed** must be verified before the data is bundled.

## 1. Candidates

| Dataset | What it holds | Size | Values | Licence | Fit |
|---|---|---|---|---|---|
| **USDA FoodData Central** (SR Legacy, Foundation Foods) | Generic foods and ingredients: grains, pulses, vegetables, fruit, dairy, meat, oils, common prepared foods | About 7,800 foods in SR Legacy | Per 100 g, with household portions | **Public domain (CC0 1.0).** USDA asks to be cited as the source | Reliable baseline for ingredients. Few Indian dishes |
| **Indian Nutrient Databank (INDB)**, Anuvaad Solutions / University of Edinburgh, 2024 | Indian cooked dishes and their ingredients | 1,014 recipes, 1,095 food items | Per 100 g and per serving; energy, protein, carbohydrate, fat, fibre and more | Described by its authors as open access; the paper is CC BY 4.0. **Licence of the data files themselves unconfirmed** | Best match for home-cooked Indian meals. Values are calculated from recipes, not lab-measured |
| **Open Food Facts** | Packaged products with barcodes, crowd-sourced | Millions worldwide; India coverage is partial but growing | Per 100 g and per serving as printed on packs | **ODbL** (database) and Database Contents Licence: attribution required, and derived databases must be shared alike | Good for packaged snacks and drinks. Quality varies by product |
| **IFCT 2017** (ICMR–National Institute of Nutrition) | Raw Indian foods, lab-analysed | 528 foods | Per 100 g | Copyright of ICMR–NIN; **no open licence found** | Authoritative, but not safe to bundle |
| UK CoFID, French CIQUAL, Canadian Nutrient File | National tables | About 3,000 each | Per 100 g | Open government licences | Not regionally useful here |

## 2. Recommendation

**INDB for dishes plus a trimmed USDA subset for ingredients, bundled as a read-only catalogue.** Open Food Facts is left out of v1.

| Reason | Detail |
|---|---|
| Coverage | Dishes (idli, dal, sabzi, biryani and so on) come from INDB; plain ingredients and generic foods come from USDA |
| Offline | Both are bundled, so search works with no network from the first day (§5.4) |
| Privacy | Nothing the user types in food search leaves the phone. A live Open Food Facts search would send search terms to a third party |
| Scope | No barcode scanner or third-party API is introduced; neither is in the PRD |

This assumes a mostly Indian diet, which is a guess. If that is wrong, USDA alone is the simplest choice.

## 3. Alternatives

| Option | When to choose it |
|---|---|
| USDA only | Licence certainty matters more than Indian dishes, or the diet is not mainly Indian |
| INDB + USDA (recommended) | Mostly home-cooked Indian food |
| Add Open Food Facts later | Packaged foods turn out to be a large share of what is logged. Would be an online search with on-device caching and an attribution notice |
| No catalogue | Everything is entered as custom foods and saved meals |

## 4. How a catalogue fits the design

| Aspect | Design |
|---|---|
| Storage | A read-only local table `local_food_catalogue` in the main database, with full-text search. It is reference data and is not synced |
| Import | A build-time script converts the source files into one compact asset (name, category, serving, energy, protein, carbohydrate, fat, fibre, source). Values are converted to integer base units once, at build time |
| Use | Picking a catalogue food copies it into the meal as a snapshot (§5.4). "Save" copies it into the user's own `food_items`, where it can be edited without touching the catalogue |
| Search order | The user's own foods and recents first, catalogue results after |
| Attribution | Each food shows its source; Settings → About lists the datasets and licences |
| Labelling | INDB recipe values are shown as estimates, because portion sizes and recipes vary between kitchens |

## 5. If the repository is public

Bundling a dataset in a public repository is redistribution.

| Dataset | Consequence |
|---|---|
| USDA | No restriction |
| INDB | Confirm the licence first. Until confirmed, the source file stays out of the repository (git-ignored) and the import script is run locally by the owner |
| Open Food Facts | Attribution and share-alike obligations apply to the derived database |

## 6. Sources

- [USDA FoodData Central](https://fdc.nal.usda.gov/) and its [data.gov catalogue entry](https://catalog.data.gov/dataset/fooddata-central)
- [Indian Nutrient Databank paper, Current Developments in Nutrition, 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11277795)
- [Open Food Facts: reusing the data](https://wiki.openfoodfacts.org/Reusing_Open_Food_Facts_Data) and [ODbL licence notes](https://wiki.openfoodfacts.org/ODBL_License)
- [IFCT 2017, ICMR–NIN](https://www.nin.res.in/ifct_book.html)
