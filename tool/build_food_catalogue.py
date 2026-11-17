#!/usr/bin/env python3
"""Builds assets/catalogue/usda_sr_legacy.json from USDA FoodData Central.

Source: "SR Legacy" CSV download from https://fdc.nal.usda.gov/download-datasets
(public domain, CC0 1.0). Values are per 100 g, as published. They are
converted once, here, to the app's integer base units.

Usage:
    python3 -I tool/build_food_catalogue.py <FoodData_Central_sr_legacy_food_csv.zip> <out.json>
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
    """Decimal text -> integer in thousandths (factor 1000), rounded half up."""
    return int((Decimal(amount) * factor).quantize(Decimal(1), rounding=ROUND_HALF_UP))


def main(zip_path, out_path):
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

    document = {
        "source": "USDA FoodData Central, SR Legacy (April 2018)",
        "source_code": "usda",
        "licence": "Public domain (CC0 1.0)",
        "version": 1,
        "per": "100 g",
        "columns": ["source_id", "name", "category", "energy_kcal_milli", "protein_mg", "carbs_mg", "fat_mg", "fibre_mg"],
        "foods": rows,
    }
    with open(out_path, "w", encoding="utf-8") as out:
        json.dump(document, out, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(rows)} foods written to {out_path}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
