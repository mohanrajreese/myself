import 'dart:convert';
import 'dart:io';

import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/settings_repository.dart';
import 'package:fitbuddy/features/food_database/data/catalogue_importer.dart';
import 'package:fitbuddy/features/food_database/data/drift_food_repository.dart';
import 'package:fitbuddy/features/food_database/domain/food.dart';
import 'package:fitbuddy/features/nutrition/domain/nutrition_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

const _dal = NutritionValues(
  energyKcalMilli: 230000,
  proteinMg: 12000,
  carbsMg: 30000,
  fatMg: 6000,
  fibreMg: 8000,
);

FoodDraft draft(String name, {bool saved = false, JunkCategory? junk}) => FoodDraft(
  name: name,
  servingLabel: '1 bowl',
  servingQtyMilli: 1000,
  servingUnit: 'bowl',
  values: _dal,
  isSaved: saved,
  junk: junk,
);

String catalogueJson({int version = 1}) => jsonEncode({
  'source': 'test',
  'source_code': 'usda',
  'version': version,
  'per': '100 g',
  'columns': [
    'source_id',
    'name',
    'category',
    'energy_kcal_milli',
    'protein_mg',
    'carbs_mg',
    'fat_mg',
    'fibre_mg',
  ],
  'foods': [
    [
      172421,
      'Lentils, mature seeds, cooked, boiled, without salt',
      'Legumes',
      116000,
      9020,
      20130,
      380,
      7900,
    ],
    [
      168878,
      'Rice, white, long-grain, regular, enriched, cooked',
      'Cereal Grains',
      130000,
      2690,
      28170,
      280,
      400,
    ],
    [99, 'Dal (100% test)', 'Legumes', 1000, 0, 0, 0, 0],
  ],
});

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftFoodRepository foods;
  late CatalogueImporter importer;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 9));
    foods = DriftFoodRepository(db, clock: time.clock, ids: SequentialIds());
    importer = CatalogueImporter(db, SettingsRepository(db, clock: time.clock));
  });
  tearDown(() => db.close());

  group('catalogue import', () {
    test('loads once per version and never enters the sync outbox', () async {
      expect(await importer.importIfNeeded(catalogueJson()), 3);
      expect(await importer.importIfNeeded(catalogueJson()), 0);
      expect(await importer.importIfNeeded(catalogueJson(version: 2)), 3);
      expect(await db.select(db.localFoodCatalogue).get(), hasLength(3));
      expect(await outboxEntries(db), isEmpty);
    });

    test('the bundled USDA asset imports and holds known values', () async {
      final json = File('assets/catalogue/usda_sr_legacy.json').readAsStringSync();
      final count = await importer.importIfNeeded(json);
      expect(count, greaterThan(7000));
      final lentils = await (db.select(
        db.localFoodCatalogue,
      )..where((t) => t.id.equals('usda:172421'))).getSingle();
      expect(lentils.energyKcalMilli, 116000);
      expect(lentils.proteinMg, 9020);
      expect(lentils.servingLabel, '100 g');
      expect(lentils.isEstimate, isFalse);
    });
  });

  group('the user\'s foods', () {
    test('create, edit, save and delete; each change is queued for sync', () async {
      final food = (await foods.create(draft('Dal (home)'))).valueOrNull!;
      expect(food.isMine, isTrue);
      await foods.update(food.id, draft('Dal, home style'));
      await foods.setSaved(food.id, true);
      expect((await foods.search('home', filter: FoodFilter.saved)).single.name, 'Dal, home style');
      await foods.delete(food.id);
      expect(await foods.search('home'), isEmpty);
      expect(await outboxEntries(db), [(table: 'food_items', id: food.id)]);
    });

    test('validation: name, serving and values', () async {
      expect((await foods.create(draft(' '))).failureOrNull?.code, 'required');
      const negative = FoodDraft(
        name: 'x',
        servingLabel: '1',
        servingQtyMilli: 1000,
        servingUnit: 'g',
        values: NutritionValues(
          energyKcalMilli: -1,
          proteinMg: 0,
          carbsMg: 0,
          fatMg: 0,
          fibreMg: 0,
        ),
      );
      expect((await foods.create(negative)).failureOrNull?.code, 'out_of_range');
      expect(await db.select(db.foodItems).get(), isEmpty);
    });
  });

  group('search', () {
    setUp(() async {
      await importer.importIfNeeded(catalogueJson());
      final dal = (await foods.create(draft('Dal (home)'))).valueOrNull!;
      await foods.create(draft('Dal makhani'));
      await foods.markUsed(dal.id, DateTime(2026, 11, 16, 13));
      await foods.markUsed(dal.id, DateTime(2026, 11, 16, 20));
    });

    test('own foods first, most used first, then the catalogue', () async {
      final results = await foods.search('dal');
      expect(results.map((f) => f.name).take(2), ['Dal (home)', 'Dal makhani']);
      expect(results.map((f) => f.source), ['mine', 'mine', 'usda']);
    });

    test('every word must match, in any order, case-insensitively', () async {
      final results = await foods.search('COOKED rice');
      expect(results.single.name, startsWith('Rice, white'));
      expect(results.single.source, FoodSources.usda);
    });

    test('% and _ in the query are taken literally', () async {
      expect((await foods.search('100%')).single.name, 'Dal (100% test)');
      expect(await foods.search('_'), isEmpty);
    });

    test('recent lists only foods that were logged, latest first', () async {
      final recent = await foods.search('', filter: FoodFilter.recent);
      expect(recent.map((f) => f.name), ['Dal (home)']);
    });

    test('an empty query shows own foods only', () async {
      expect((await foods.search('')).every((f) => f.isMine), isTrue);
    });
  });

  test('adopting a catalogue food copies it once into the user\'s foods', () async {
    await importer.importIfNeeded(catalogueJson());
    final lentils = (await foods.search('lentils')).single;
    final first = (await foods.adopt(lentils)).valueOrNull!;
    final second = (await foods.adopt(lentils)).valueOrNull!;
    expect(first.isMine, isTrue);
    expect(second.id, first.id);
    expect(first.values, lentils.values);
    expect(first.servingQtyMilli, 100000);
    expect(first.servingUnit, 'g');
  });
}
