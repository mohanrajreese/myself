import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/settings_repository.dart';

/// Loads a bundled catalogue JSON (built by tool/build_food_catalogue.py)
/// into the read-only `local_food_catalogue` table. Runs once per catalogue
/// version; later calls do nothing.
final class CatalogueImporter {
  CatalogueImporter(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// [json] is the asset's text. Returns the number of foods imported, or 0
  /// when this version is already present.
  Future<int> importIfNeeded(String json) async {
    final doc = jsonDecode(json) as Map<String, Object?>;
    final source = doc['source_code']! as String;
    final version = doc['version']! as int;
    final key = 'catalogue_version_$source';
    if (await _settings.read(key) == version) return 0;

    final columns = (doc['columns']! as List<Object?>).cast<String>();
    int col(String name) => columns.indexOf(name);
    final iId = col('source_id'), iName = col('name'), iCat = col('category');
    final iKcal = col('energy_kcal_milli'), iP = col('protein_mg'), iC = col('carbs_mg');
    final iF = col('fat_mg'), iFi = col('fibre_mg');
    final iHl = col('household_label'), iHw = col('household_weight_mg'), iCo = col('has_conflict');
    Object? at(List<Object?> row, int i) => i < 0 || i >= row.length ? null : row[i];
    final estimate = doc['is_estimate'] == true;
    final per = doc['per'] as String? ?? '100 g';
    final perGrams = int.tryParse(per.split(' ').first) ?? 100;

    final foods = (doc['foods']! as List<Object?>).cast<List<Object?>>();
    await _db.transaction(() async {
      await (_db.delete(_db.localFoodCatalogue)..where((t) => t.source.equals(source))).go();
      await _db.batch((batch) {
        batch.insertAll(_db.localFoodCatalogue, [
          for (final f in foods)
            LocalFoodCatalogueCompanion.insert(
              id: '$source:${f[iId]}',
              source: source,
              name: f[iName]! as String,
              category: f[iCat]! as String,
              servingLabel: per,
              servingWeightMg: perGrams * 1000,
              energyKcalMilli: f[iKcal]! as int,
              proteinMg: f[iP]! as int,
              carbsMg: f[iC]! as int,
              fatMg: f[iF]! as int,
              fibreMg: f[iFi]! as int,
              isEstimate: Value(estimate),
              householdLabel: Value(at(f, iHl) as String?),
              householdWeightMg: Value(at(f, iHw) as int?),
              hasConflict: Value(at(f, iCo) == true),
            ),
        ]);
      });
    });
    await _settings.write(key, version);
    return foods.length;
  }
}
