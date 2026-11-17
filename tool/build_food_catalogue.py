#!/usr/bin/env python3
"""Builds the bundled food catalogues in assets/catalogue/.

USDA: "SR Legacy" CSV download from https://fdc.nal.usda.gov/download-datasets
(public domain, CC0 1.0).

INDB: INDB.xlsx from https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-
(Vijayakumar A, Dubasi HB, Awasthi A, Jaacks LM. Indian Nutrient Databank (INDB):
a comprehensive open-access resource for Indian food composition.
Current Developments in Nutrition, 2024). Values are calculated from recipes,
so they are marked as estimates. Needs openpyxl.

Values are per 100 g, as published, converted once here to the app's integer
base units.

Usage:
    python3 -I tool/build_food_catalogue.py usda <FoodData_Central_sr_legacy_food_csv.zip> <out.json>
    python3 -I tool/build_food_catalogue.py indb <INDB.xlsx> <out.json>
"""
import csv
import io
import json
import sys
import zipfile
from decimal import ROUND_HALF_UP, Decimal

# FoodData Central nutrient ids.
NUTRIENTS = {"1008": "kcal", "1003": "protein", "1005": "carbs", "1004": "fat", "1079": "fibre"}


def read(archive, suffix):
    name = next(n for n in archive.namelist() if n.endswith(suffix))
    with archive.open(name) as handle:
        yield from csv.DictReader(io.TextIOWrapper(handle, encoding="utf-8"))


def scaled(amount, factor):
    """Decimal value -> integer in thousandths (factor 1000), rounded half up.
    Negative values (none expected) are clamped to zero."""
    result = int((Decimal(amount) * factor).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    return max(result, 0)


COLUMNS = ["source_id", "name", "category", "energy_kcal_milli", "protein_mg", "carbs_mg", "fat_mg", "fibre_mg"]


def write(out_path, document):
    with open(out_path, "w", encoding="utf-8") as out:
        json.dump(document, out, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(document['foods'])} foods written to {out_path}")


def build_indb(xlsx_path, out_path):
    import openpyxl  # only needed for INDB

    sheet = openpyxl.load_workbook(xlsx_path, read_only=True).worksheets[0]
    rows = sheet.iter_rows(values_only=True)
    header = {name: i for i, name in enumerate(next(rows))}

    def value(row, column):
        cell = row[header[column]]
        if cell in (None, "", "NA"):
            return None
        return Decimal(str(cell))

    foods = []
    flagged = []
    for row in rows:
        code, name = row[header["food_code"]], row[header["food_name"]]
        if not code or not name:
            continue
        kcal = value(row, "energy_kcal") or Decimal(0)
        protein = value(row, "protein_g") or Decimal(0)
        carbs = value(row, "carb_g") or Decimal(0)
        fat = value(row, "fat_g") or Decimal(0)
        fibre = value(row, "fibre_g") or Decimal(0)

        # Flag (do not drop) dishes whose stated energy contradicts their own
        # macronutrients by more than 25 % and 30 kcal: one of the numbers is
        # wrong. The app shows a warning and the user can correct the values.
        from_macros = 4 * protein + 4 * carbs + 9 * fat
        conflict = abs(kcal - from_macros) > 30 and abs(kcal - from_macros) > Decimal("0.25") * kcal
        if conflict:
            flagged.append(str(code))

        # Household serving ("1 bowl"), weight derived from per-serving vs
        # per-100 g energy, as published. Left empty when it cannot be derived.
        unit = (row[header["servings_unit"]] or "").strip()
        per_serving_kcal = value(row, "unit_serving_energy_kcal")
        household_label, household_mg = None, None
        if unit and per_serving_kcal and kcal > 0:
            household_label = f"1 {unit}"
            household_mg = scaled(per_serving_kcal / kcal * 100, 1000)

        foods.append([
            str(code),
            str(name).strip(),
            "Indian dishes",
            scaled(kcal, 1000),
            scaled(protein, 1000),
            scaled(carbs, 1000),
            scaled(fat, 1000),
            scaled(fibre, 1000),
            household_label,
            household_mg,
            conflict,
        ])
    foods.sort(key=lambda r: r[1].lower())
    print(f"{len(flagged)} dishes flagged (energy contradicts macronutrients): {', '.join(flagged)}")
    write(out_path, {
        "source": "Indian Nutrient Databank (INDB), Vijayakumar et al., Current Developments in Nutrition 2024",
        "source_code": "indb",
        "licence": "Published as open access by its authors; no licence file in the source repository",
        "version": 2,
        "per": "100 g",
        "is_estimate": True,
        "conflict_rule": "Stated energy differs from 4/4/9 kcal per g of protein, carbohydrate and fat by more than 25 % and 30 kcal",
        "columns": COLUMNS + ["household_label", "household_weight_mg", "has_conflict"],
        "foods": foods,
    })


def build_usda(zip_path, out_path):
    with zipfile.ZipFile(zip_path) as archive:
        categories = {row["id"]: row["description"] for row in read(archive, "/food_category.csv")}
        foods = {
            row["fdc_id"]: {"name": row["description"].strip(), "category": categories.get(row["food_category_id"], "Other")}
            for row in read(archive, "/food.csv")
            if row["data_type"] == "sr_legacy_food"
        }
        values = {}
        for row in read(archive, "/food_nutrient.csv"):
            key = NUTRIENTS.get(row["nutrient_id"])
            if key and row["fdc_id"] in foods and row["amount"] != "":
                values.setdefault(row["fdc_id"], {})[key] = row["amount"]

    rows = []
    for fdc_id, food in foods.items():
        nutrient = values.get(fdc_id, {})
        # A food without an energy value cannot be logged meaningfully.
        if "kcal" not in nutrient:
            continue
        rows.append([
            int(fdc_id),
            food["name"],
            food["category"],
            scaled(nutrient["kcal"], 1000),            # thousandths of a kcal per 100 g
            scaled(nutrient.get("protein", "0"), 1000),  # mg per 100 g
            scaled(nutrient.get("carbs", "0"), 1000),
            scaled(nutrient.get("fat", "0"), 1000),
            scaled(nutrient.get("fibre", "0"), 1000),
        ])
    rows.sort(key=lambda r: r[1].lower())

    write(out_path, {
        "source": "USDA FoodData Central, SR Legacy (April 2018)",
        "source_code": "usda",
        "licence": "Public domain (CC0 1.0)",
        "version": 1,
        "per": "100 g",
        "columns": COLUMNS,
        "foods": rows,
    })


if __name__ == "__main__":
    {"usda": build_usda, "indb": build_indb}[sys.argv[1]](sys.argv[2], sys.argv[3])
