import 'package:drift/native.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/synced_tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> enqueue(String table) => db.customStatement(
    'INSERT INTO sync_outbox (entity_table, entity_id, enqueued_at, next_attempt_at) '
    "VALUES (?, 'id-1', '2026-11-16T00:00:00.000Z', '2026-11-16T00:00:00.000Z')",
    [table],
  );

  test('accepts every synced table', () async {
    for (final table in syncedTableNames) {
      await enqueue(table);
      await db.customStatement('DELETE FROM sync_outbox');
    }
  });

  test('refuses local-only and private tables', () async {
    for (final table in [
      'local_app_settings',
      'local_bowel_logs',
      'local_private_habit_logs',
      'local_medication_logs',
      'local_screen_time_apps',
      'local_step_readings',
      'local_timer_sessions',
      'local_timer_events',
      'local_notification_state',
      'local_step_daily',
      'local_workout_route_points',
      'anything_else',
    ]) {
      await expectLater(enqueue(table), throwsA(anything), reason: table);
    }
    final rows = await db.customSelect('SELECT count(*) AS n FROM sync_outbox').getSingle();
    expect(rows.read<int>('n'), 0);
  });

  test('the allow-list never contains a local_ table', () {
    expect(syncedTableNames.where((name) => name.startsWith('local_')), isEmpty);
  });

  test('one pending entry per row: a second enqueue of the same row is a conflict', () async {
    await enqueue('weight_logs');
    await expectLater(enqueue('weight_logs'), throwsA(anything));
  });

  test('foreign keys are enforced on the in-memory database used by tests', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.single, 1);
  });
}
