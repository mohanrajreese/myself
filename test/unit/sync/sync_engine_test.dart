import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/outbox.dart';
import 'package:fitbuddy/core/database/synced_tables.dart';
import 'package:fitbuddy/core/sync/sync_engine.dart';
import 'package:fitbuddy/core/sync/sync_remote.dart';
import 'package:fitbuddy/core/sync/sync_tables.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/memory_sync_remote.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late MemorySyncRemote remote;
  late SyncEngine engine;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime.utc(2026, 11, 18, 9));
    remote = MemorySyncRemote(clock: () => time.now);
    engine = SyncEngine(db: db, remote: remote, clock: time.clock, random: Random(1));
  });
  tearDown(() => db.close());

  String iso(DateTime t) => t.toUtc().toIso8601String();

  Future<void> addWeight(String id, int grams, {DateTime? updated, bool enqueue = true}) async {
    final u = updated ?? time.now;
    await db.customInsert(
      'INSERT INTO weight_logs (id, created_at, updated_at, weight_g, entry_unit, occurred_at, local_date, tz) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET weight_g = excluded.weight_g, updated_at = excluded.updated_at',
      variables: [
        for (final v in [id, iso(u), iso(u), grams, 'kg', iso(u), '2026-11-18', 'Asia/Kolkata'])
          if (v is int) Variable.withInt(v) else Variable.withString(v as String),
      ],
    );
    if (enqueue) await db.enqueueForSync('weight_logs', id, time.now);
  }

  Future<int> outboxCount() async =>
      (await db.customSelect('SELECT count(*) AS n FROM sync_outbox').getSingle()).read<int>('n');

  Future<int?> localWeight(String id) async =>
      (await db
              .customSelect('SELECT weight_g FROM weight_logs WHERE id = ?', variables: [Variable.withString(id)])
              .getSingleOrNull())
          ?.read<int>('weight_g');

  group('push', () {
    test('sends queued rows and empties the outbox', () async {
      await addWeight('w1', 91800);
      await addWeight('w2', 91500);
      final r = await engine.push();
      expect(r.pushed, 2);
      expect(await outboxCount(), 0);
      expect(remote.rows('weight_logs').map((r) => r['weight_g']), containsAll([91800, 91500]));
    });

    test('pushing twice changes nothing (idempotent)', () async {
      await addWeight('w1', 91800);
      await engine.push();
      await db.enqueueForSync('weight_logs', 'w1', time.now);
      await engine.push();
      expect(remote.rows('weight_logs'), hasLength(1));
    });

    test('a row changed while sending stays queued', () async {
      await addWeight('w1', 91800);
      remote.beforeUpsert = () async {
        time.now = time.now.add(const Duration(seconds: 1));
        await addWeight('w1', 90000, enqueue: false);
      };
      await engine.push();
      expect(await outboxCount(), 1);
    });

    test('a failure keeps the entry, backs off and stores only a code', () async {
      await addWeight('w1', 91800);
      remote.failNext = const SyncRemoteException('network');
      final r = await engine.push();
      expect(r.failed, 1);
      final row = await db.customSelect('SELECT * FROM sync_outbox').getSingle();
      expect(row.read<int>('attempts'), 1);
      expect(row.read<String>('last_error_code'), 'network');
      final next = DateTime.parse(row.read<String>('next_attempt_at'));
      final wait = next.difference(time.now).inMilliseconds;
      expect(wait, inInclusiveRange(8000, 12000)); // 10 s ± 20 %
      // Not due yet: nothing is sent.
      expect((await engine.push()).pushed, 0);
      time.now = time.now.add(const Duration(seconds: 13));
      expect((await engine.push()).pushed, 1);
    });

    test('backoff is capped at one hour', () {
      expect(SyncEngine.backoff(20, Random(3)).inMinutes, inInclusiveRange(48, 72));
    });

    test('an authentication failure pauses pushing', () async {
      await addWeight('w1', 91800);
      await addWeight('w2', 91500);
      remote.failNext = const SyncRemoteException('auth', auth: true);
      final r = await engine.push();
      expect(r.authPaused, isTrue);
      expect(await outboxCount(), 2);
    });

    test('step totals are upserted on (user_id, log_date)', () async {
      await db.customInsert(
        'INSERT INTO step_logs (id, created_at, updated_at, log_date, steps, source, timezone) '
        "VALUES ('s1', ?1, ?1, '2026-11-18', 8000, 'phone_sensor', 'Asia/Kolkata')",
        variables: [Variable.withString(iso(time.now))],
      );
      await db.enqueueForSync('step_logs', 's1', time.now);
      await engine.push();
      expect(remote.conflictKeys['step_logs'], 'user_id,log_date');
    });

    test('booleans and JSON documents are sent as their real types', () async {
      final rule = jsonEncode({
        'v': 1,
        'type': 'daily',
        'times': [480],
      });
      await db.customInsert(
        'INSERT INTO reminders (id, created_at, updated_at, kind, title, schedule, condition, channel_key, vibrate, '
        'snooze_default_min, priority, quiet_hours_behaviour, exact, enabled) '
        "VALUES ('r1', ?1, ?1, 'water', 'Water', ?2, 'always', 'hydration', 1, 10, 'normal', 'defer', 0, 1)",
        variables: [Variable.withString(iso(time.now)), Variable.withString(rule)],
      );
      await db.enqueueForSync('reminders', 'r1', time.now);
      await engine.push();
      final sent = remote.rows('reminders').single;
      expect(sent['vibrate'], isTrue);
      expect(sent['exact'], isFalse);
      expect(sent['schedule'], isA<Map<String, Object?>>());
    });
  });

  group('pull', () {
    Map<String, Object?> cloudWeight(String id, int g, DateTime updated) => {
      'id': id,
      'user_id': 'user-1',
      'created_at': iso(updated),
      'updated_at': iso(updated),
      'deleted_at': null,
      'weight_g': g,
      'entry_unit': 'kg',
      'occurred_at': iso(updated),
      'local_date': '2026-11-17',
      'tz': 'Asia/Kolkata',
      'notes': null,
    };

    test('restores rows for a returning user without queueing them again', () async {
      remote.seed('weight_logs', [cloudWeight('w1', 92000, time.now), cloudWeight('w2', 91700, time.now)]);
      final r = await engine.pull();
      expect(r.pulled, 2);
      expect(await localWeight('w1'), 92000);
      expect(await outboxCount(), 0);
    });

    test('a pending local change wins over the pulled row', () async {
      await addWeight('w1', 90000);
      remote.seed('weight_logs', [cloudWeight('w1', 95000, time.now.add(const Duration(minutes: 5)))]);
      await engine.pull();
      expect(await localWeight('w1'), 90000);
    });

    test('a newer local row is kept; an older one is replaced', () async {
      await addWeight('w1', 90000, enqueue: false);
      remote.seed('weight_logs', [cloudWeight('w1', 95000, time.now.subtract(const Duration(hours: 1)))]);
      await engine.pull();
      expect(await localWeight('w1'), 90000);
      remote.seed('weight_logs', [cloudWeight('w1', 96000, time.now.add(const Duration(hours: 1)))]);
      await engine.pull();
      expect(await localWeight('w1'), 96000);
    });

    test('pages through many rows and saves a cursor per table', () async {
      remote.pageSize = 3;
      remote.seed('weight_logs', [
        for (var i = 0; i < 8; i++) cloudWeight('w$i', 90000 + i, time.now.add(Duration(seconds: i))),
      ]);
      final r = await engine.pull();
      expect(r.pulled, 8);
      final cursor = await db
          .customSelect("SELECT * FROM local_sync_cursors WHERE table_name = 'weight_logs'")
          .getSingle();
      expect(cursor.read<String>('cursor_id'), 'w7');
      // Nothing new: only the 30-second overlap is fetched again, changing nothing.
      final again = await engine.pull();
      expect(again.failed, 0);
      expect(await localWeight('w7'), 90007);
    });

    test('tombstones arrive as deleted rows', () async {
      final row = cloudWeight('w1', 92000, time.now)..['deleted_at'] = iso(time.now);
      remote.seed('weight_logs', [row]);
      await engine.pull();
      final deleted = await db.customSelect("SELECT deleted_at FROM weight_logs WHERE id = 'w1'").getSingle();
      expect(deleted.read<String?>('deleted_at'), isNotNull);
    });
  });

  test('sync now pushes, pulls and reports what is waiting', () async {
    await addWeight('w1', 91800);
    expect(await engine.pending(), 1);
    final r = await engine.syncNow();
    expect(r.pushed, 1);
    expect(await engine.pending(), 0);
  });

  test('JSON column list matches the jsonb columns in the Supabase migrations', () {
    final sql = Directory(
      'supabase/migrations',
    ).listSync().whereType<File>().map((f) => f.readAsStringSync()).join('\n');
    final found = <String, Set<String>>{};
    for (final m in RegExp(r'create table public\.(\w+)\s*\((.*?)\n\);', dotAll: true).allMatches(sql)) {
      for (final line in m.group(2)!.split('\n')) {
        final c = RegExp(r'^\s*(\w+)\s+jsonb').firstMatch(line);
        if (c != null) (found[m.group(1)!] ??= {}).add(c.group(1)!);
      }
    }
    found.removeWhere((t, _) => !syncedTableNames.contains(t));
    expect(jsonColumns, found);
  });
}
