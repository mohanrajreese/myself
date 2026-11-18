import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in [1, 2, 3, 4, 5, 6, 7, 8]) {
    test('a version $from database upgrades to the current schema', () async {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      await verifier.migrateAndValidate(db, 8);
      await db.close();
    });
  }

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
