import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v8.dart' as v8;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('every older version is tested', () {
    // Fails when a version is added without extending the loop below.
    expect(AppDatabase(DatabaseConnection(NativeDatabase.memory())).schemaVersion, 9);
  });

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8]) {
    test('a version $from database upgrades to the current schema', () async {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      await verifier.migrateAndValidate(db, db.schemaVersion);
      final broken = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(broken, isEmpty);
      await db.close();
    });
  }

  test('rows from every area written under version 8 survive the upgrade to 9', () async {
    final schema = await verifier.schemaAt(8);
    final old = v8.DatabaseAtV8(schema.newConnection());
    const t = '2026-11-16T03:30:00.000Z';
    for (final sql in [
      'INSERT INTO weight_logs (id, created_at, updated_at, weight_g, entry_unit, occurred_at, local_date, tz) '
          "VALUES ('w1', '$t', '$t', 91800, 'kg', '$t', '2026-11-16', 'UTC')",
      'INSERT INTO step_logs (id, created_at, updated_at, log_date, steps, source, timezone) '
          "VALUES ('s1', '$t', '$t', '2026-11-16', 8000, 'phone_sensor', 'UTC')",
      "INSERT INTO local_recovery_logs (local_date, is_rest_day, updated_at) VALUES ('2026-11-16', 1, '$t')",
      'INSERT INTO sync_outbox (entity_table, entity_id, enqueued_at, next_attempt_at) '
          "VALUES ('weight_logs', 'w1', '$t', '$t')",
    ]) {
      await old.customStatement(sql);
    }
    await old.close();

    final db = AppDatabase(schema.newConnection());
    expect((await db.select(db.weightLogs).get()).single.weightG, 91800);
    expect((await db.select(db.stepLogs).get()).single.steps, 8000);
    expect((await db.select(db.localRecoveryLogs).get()).single.isRestDay, isTrue);
    expect(await db.select(db.syncOutbox).get(), hasLength(1));
    expect(await db.select(db.localSyncCursors).get(), isEmpty);
    await db.close();
  });

  test('rows written under version 1 survive the upgrade', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old.customStatement(
      'INSERT INTO weight_logs (id, created_at, updated_at, weight_g, entry_unit, occurred_at, '
      "local_date, tz) VALUES ('w1', '2026-11-16T03:30:00.000Z', '2026-11-16T03:30:00.000Z', "
      "91800, 'kg', '2026-11-16T03:30:00.000Z', '2026-11-16', 'Asia/Kolkata')",
    );
    await old.customStatement(
      'INSERT INTO local_app_settings (key, value_json, updated_at) '
      "VALUES ('theme_mode', '\"dark\"', '2026-11-16T03:30:00.000Z')",
    );
    await old.close();

    final db = AppDatabase(schema.newConnection());
    final weights = await db.select(db.weightLogs).get();
    expect(weights.single.weightG, 91800);
    expect((await db.select(db.localAppSettings).get()).single.valueJson, '"dark"');

    // The new tables exist and accept rows; the outbox accepts them too.
    await db.customStatement(
      'INSERT INTO water_logs (id, created_at, updated_at, amount_ml, occurred_at, local_date, tz) '
      "VALUES ('x1', '2026-11-17T03:30:00.000Z', '2026-11-17T03:30:00.000Z', 250, "
      "'2026-11-17T03:30:00.000Z', '2026-11-17', 'Asia/Kolkata')",
    );
    await db.customStatement(
      'INSERT INTO sync_outbox (entity_table, entity_id, enqueued_at, next_attempt_at) '
      "VALUES ('water_logs', 'x1', '2026-11-17T03:30:00.000Z', '2026-11-17T03:30:00.000Z')",
    );
    await db.close();
  });
}
