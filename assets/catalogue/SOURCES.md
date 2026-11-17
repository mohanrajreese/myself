# Food catalogue sources

Both files are built by `tool/build_food_catalogue.py`. Values are per 100 g, as published, converted to integer base units.

| File | Source | Terms | Foods |
|---|---|---|---|
| `usda_sr_legacy.json` | U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, SR Legacy (April 2018). fdc.nal.usda.gov | Public domain (CC0 1.0); USDA asks to be cited as the source | 7,793 |
| `indb.json` | Vijayakumar A, Dubasi HB, Awasthi A, Jaacks LM. Indian Nutrient Databank (INDB): a comprehensive open-access resource for Indian food composition. *Current Developments in Nutrition*, 2024. github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB- | Described by its authors as open access and usable by researchers, government, and the private and third sectors. The article is CC BY 4.0. The data repository itself carries no licence file | 980 of 1,014 |

INDB values are calculated from recipes (with nutrient retention factors), not measured, so the app labels them as estimates. 34 dishes are left out because their stated energy contradicts their own protein, carbohydrate and fat (more than 25 % and 30 kcal apart); the build script prints their codes.
