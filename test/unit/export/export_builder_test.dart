import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/private_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/data_export/data/export_builder.dart';
import 'package:fitbuddy/features/data_export/domain/export.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late PrivateDatabase privateDb;
  late ExportBuilder builder;
  const stamp = '2026-11-16T09:00:00.000Z';

  setUp(() async {
    db = memoryDatabase();
    privateDb = memoryPrivateDatabase();
    builder = ExportBuilder(db: db, privateDb: privateDb, clock: MutableClock(DateTime(2026, 11, 18)).clock);
    for (final (id, date, g) in [('w1', '2026-11-01', 92000), ('w2', '2026-11-16', 91800)]) {
      await db.customStatement(
        'INSERT INTO weight_logs (id, created_at, updated_at, weight_g, entry_unit, occurred_at, local_date, tz, notes) '
        "VALUES (?, ?2, ?2, ?, 'kg', ?2, ?, 'UTC', 'after \"gym\", tired')",
        [id, stamp, g, date],
      );
    }
    for (final (id, date) in [('m1', '2026-11-01'), ('m2', '2026-11-16')]) {
      await db.customStatement(
        'INSERT INTO meal_logs (id, created_at, updated_at, meal_category, occurred_at, local_date, tz, has_photo) '
        "VALUES (?, ?2, ?2, 'lunch', ?2, ?, 'UTC', 0)",
        [id, stamp, date],
      );
      await db.customStatement(
        'INSERT INTO meal_food_items (id, created_at, updated_at, meal_log_id, food_name, quantity_milli, unit, '
        'energy_kcal_milli, protein_mg, carbs_mg, fat_mg, fibre_mg, sort_order) '
        "VALUES (?, ?2, ?2, ?, 'Dal', 1000, 'serving', 300000, 1, 1, 1, 1, 0)",
        ['i$id', stamp, id],
      );
    }
    await privateDb.customStatement(
      'INSERT INTO local_bowel_logs (id, created_at, updated_at, occurred_at, local_date, tz, count, consistency, straining) '
      "VALUES ('b1', ?1, ?1, ?1, '2026-11-16', 'UTC', 1, 'normal', 0)",
      [stamp],
    );
  });
  tearDown(() async {
    await db.close();
    await privateDb.close();
  });

  Map<String, Object?> json(List<int> zip, {String? password}) {
    final a = ZipDecoder().decodeBytes(zip, password: password);
    return jsonDecode(utf8.decode(a.findFile('praxis.json')!.content)) as Map<String, Object?>;
  }

  test('JSON export holds every synced table; private data is left out unless asked', () async {
    final out = json(await builder.build(const ExportOptions()));
    final tables = out['tables']! as Map<String, Object?>;
    expect((tables['weight_logs']! as List), hasLength(2));
    expect(tables.keys.where((k) => k.startsWith('private.')), isEmpty);
    expect(out['includes_private'], isFalse);
    expect(jsonEncode(out), isNot(contains('bowel')));

    final withPrivate = json(await builder.build(const ExportOptions(includePrivate: true)));
    expect(((withPrivate['tables']! as Map)['private.local_bowel_logs']! as List), hasLength(1));
  });

  test('a passphrase encrypts the zip; the wrong one cannot read it', () async {
    final zip = await builder.build(const ExportOptions(passphrase: 'correct horse'));
    expect(() => json(zip), throwsA(anything)); // no passphrase, no content
    expect(json(zip, password: 'correct horse')['format'], 'praxis-export');
    expect(() => json(zip, password: 'wrong pass'), throwsA(anything));
  });

  test('a date range applies to logs and to their child rows', () async {
    final out = json(await builder.build(ExportOptions(from: LocalDate(2026, 11, 10), to: LocalDate(2026, 11, 18))));
    final t = out['tables']! as Map<String, Object?>;
    expect([for (final r in t['weight_logs']! as List) (r as Map)['id']], ['w2']);
    expect([for (final r in t['meal_food_items']! as List) (r as Map)['meal_log_id']], ['m2']);
  });

  test('CSV export writes one file per table, quoting where needed', () async {
    final a = ZipDecoder().decodeBytes(await builder.build(const ExportOptions(format: ExportFormat.csv)));
    final csv = utf8.decode(a.findFile('weight_logs.csv')!.content);
    expect(csv.split('\n').first, startsWith('id,created_at,updated_at'));
    expect(csv, contains('"after ""gym"", tired"'));
    expect(a.findFile('manifest.json'), isNotNull);
    expect(a.findFile('step_logs.csv'), isNull); // empty tables are left out
  });

  test('options are validated', () {
    expect(const ExportOptions(passphrase: 'short').problems, ['passphrase_short']);
    expect(ExportOptions(from: LocalDate(2026, 11, 2), to: LocalDate(2026, 11, 1)).problems, ['range_reversed']);
  });
}
