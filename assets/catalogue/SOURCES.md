# Food catalogue sources

Both files are built by `tool/build_food_catalogue.py`. Values are per 100 g, as published, converted to integer base units.

| File | Source | Terms | Foods |
|---|---|---|---|
| `usda_sr_legacy.json` | U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, SR Legacy (April 2018). fdc.nal.usda.gov | Public domain (CC0 1.0); USDA asks to be cited as the source | 7,793 |
| `indb.json` | Vijayakumar A, Dubasi HB, Awasthi A, Jaacks LM. Indian Nutrient Databank (INDB): a comprehensive open-access resource for Indian food composition. *Current Developments in Nutrition*, 2024. github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB- | Described by its authors as open access and usable by researchers, government, and the private and third sectors. The article is CC BY 4.0. The data repository itself carries no licence file | 1,014 |

INDB values are calculated from recipes (with nutrient retention factors), not measured, so the app labels them as estimates. All 1,014 dishes are included as published. 34 are flagged because their stated energy contradicts their own protein, carbohydrate and fat (more than 25 % and 30 kcal apart); the app shows a warning on them and the build script prints their codes. 917 dishes carry INDB's household serving (for example "1 idli", about 25 g), with its weight derived from the published per-serving and per-100 g energy; these sizes vary widely in the source.

Any catalogue food can be edited. Editing saves the user's own copy, linked to the original by `catalogue_ref`; the copy replaces the original in search and syncs like any of the user's foods. Deleting the copy brings the original back.
