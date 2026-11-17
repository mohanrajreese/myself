import 'package:drift/drift.dart';

import '../utils/local_date.dart';
import 'converters.dart';
import 'synced_tables.dart';
import 'tables/local_tables.dart';
import 'tables/profile_tables.dart';
import 'tables/tracking_tables.dart';

part 'app_database.g.dart';

/// Main database (`fitbuddy.db`): synced tables and local operational tables.
/// Private records live in `PrivateDatabase`, which sync code cannot import.
@DriftDatabase(
  tables: [
    Profiles,
    UserGoals,
    NutritionGoals,
    WeightLogs,
    SyncOutbox,
    LocalAppSettings,
    BodyMeasurements,
    WaterLogs,
    FoodItems,
    MealLogs,
    MealFoodItems,
    SavedMeals,
    SleepLogs,
    DailyHealthCheckins,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const databaseName = 'fitbuddy';

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        // Phase 2: body measurements, water, nutrition, sleep, wellness.
        for (final table in <TableInfo<Table, Object?>>[
          bodyMeasurements,
          waterLogs,
          foodItems,
          mealLogs,
          mealFoodItems,
          savedMeals,
          sleepLogs,
          dailyHealthCheckins,
        ]) {
          await migrator.createTable(table);
        }
        for (final index in allSchemaEntities.whereType<Index>()) {
          if (index.entityName != 'weight_logs_local_date') await migrator.create(index);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _installOutboxAllowList();
    },
  );

  /// Removes every row from every table (used when the device is handed to
  /// a different account; call C11).
  Future<void> eraseAllData() => transaction(() async {
    await customStatement('PRAGMA defer_foreign_keys = ON');
    for (final table in allTables) {
      await delete(table).go();
    }
  });

  /// Rebuilt on every open so it always matches [syncedTableNames].
  Future<void> _installOutboxAllowList() async {
    final allowed = syncedTableNames.map((name) => "'$name'").join(', ');
    for (final event in const ['INSERT', 'UPDATE OF entity_table']) {
      final name = 'sync_outbox_allowlist_${event.split(' ').first.toLowerCase()}';
      await customStatement('DROP TRIGGER IF EXISTS $name');
      await customStatement(
        'CREATE TRIGGER $name BEFORE $event ON sync_outbox '
        'WHEN NEW.entity_table NOT IN ($allowed) '
        "BEGIN SELECT RAISE(ABORT, 'table is not syncable'); END",
      );
    }
  }
}
