import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/synced_tables.dart';
import '../utils/clock.dart';
import 'sync_remote.dart';
import 'sync_tables.dart';

/// What one sync run did.
final class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.failed = 0,
    this.errorCode,
    this.authPaused = false,
  });
  final int pushed;
  final int pulled;
  final int failed;
  final String? errorCode;
  final bool authPaused;

  SyncResult operator +(SyncResult o) => SyncResult(
    pushed: pushed + o.pushed,
    pulled: pulled + o.pulled,
    failed: failed + o.failed,
    errorCode: o.errorCode ?? errorCode,
    authPaused: authPaused || o.authPaused,
  );
}

/// Push and pull for the synced tables (03-database.md §6). Has no access to
/// the private database (architecture test).
final class SyncEngine {
  SyncEngine({required this.db, required this.remote, required this.clock, Random? random})
    : _random = random ?? Random();

  final AppDatabase db;
  final SyncRemote remote;
  final Clock clock;
  final Random _random;

  static const pushBatch = 100;
  static const pullPage = 500;
  static const overlap = Duration(seconds: 30);

  /// `min(2^attempts × 5 s, 1 h)` with ±20 % jitter.
  static Duration backoff(int attempts, Random random) {
    final base = attempts >= 10 ? 3600000 : min(3600000, (1 << attempts) * 5000);
    final jitter = 0.8 + random.nextDouble() * 0.4;
    return Duration(milliseconds: (base * jitter).round());
  }

  Future<int> pending() async =>
      (await db.customSelect('SELECT count(*) AS n FROM sync_outbox').getSingle()).read<int>('n');

  /// Push, pull, then push anything that arrived meanwhile.
  Future<SyncResult> syncNow() async {
    var r = await push();
    if (r.authPaused) return r;
    r += await pull();
    if (r.authPaused) return r;
    return r + await push();
  }

  TableInfo<Table, dynamic> _table(String name) =>
      db.allTables.firstWhere((t) => t.actualTableName == name);

  String _iso(DateTime t) => t.toUtc().toIso8601String();

  Future<SyncResult> push() async {
    final now = clock.now();
    final due = await db
        .customSelect(
          'SELECT entity_table, entity_id, attempts FROM sync_outbox WHERE next_attempt_at <= ? ORDER BY seq',
          variables: [Variable.withString(_iso(now))],
        )
        .get();
    var result = const SyncResult();
    for (final table in syncedTableNames) {
      final entries = due.where((r) => r.read<String>('entity_table') == table).toList();
      for (var i = 0; i < entries.length; i += pushBatch) {
        final chunk = entries.sublist(i, min(i + pushBatch, entries.length));
        final r = await _pushChunk(table, chunk);
        result += r;
        if (r.authPaused) return result;
      }
    }
    return result;
  }

  Future<SyncResult> _pushChunk(String table, List<QueryRow> entries) async {
    final ids = [for (final e in entries) e.read<String>('entity_id')];
    final marks = List.filled(ids.length, '?').join(', ');
    final rows = await db
        .customSelect(
          'SELECT * FROM $table WHERE id IN ($marks)',
          variables: [for (final id in ids) Variable.withString(id)],
        )
        .get();
    final found = {for (final r in rows) r.data['id']! as String: r.data};
    // A queued row that no longer exists has nothing to send.
    for (final id in ids.where((id) => !found.containsKey(id))) {
      await _dropEntry(table, id);
    }
    if (found.isEmpty) return const SyncResult();
    final info = _table(table);
    final payload = [for (final r in found.values) _toRemote(info, table, r)];
    try {
      await remote.upsert(table, payload, onConflict: conflictKeys[table]);
    } on SyncRemoteException catch (e) {
      if (e.auth) return SyncResult(failed: found.length, errorCode: e.code, authPaused: true);
      final now = clock.now();
      for (final entry in entries.where((e) => found.containsKey(e.read<String>('entity_id')))) {
        final attempts = entry.read<int>('attempts') + 1;
        await db.customUpdate(
          'UPDATE sync_outbox SET attempts = ?, next_attempt_at = ?, last_error_code = ? '
          'WHERE entity_table = ? AND entity_id = ?',
          variables: [
            Variable.withInt(attempts),
            Variable.withString(_iso(now.add(backoff(attempts, _random)))),
            Variable.withString(e.code),
            Variable.withString(table),
            Variable.withString(entry.read<String>('entity_id')),
          ],
          updates: {db.syncOutbox},
        );
      }
      return SyncResult(failed: found.length, errorCode: e.code);
    }
    // Remove an entry only if the row is unchanged since it was read.
    for (final r in found.values) {
      await db.customUpdate(
        'DELETE FROM sync_outbox WHERE entity_table = ? AND entity_id = ? '
        'AND (SELECT updated_at FROM $table WHERE id = ?) = ?',
        variables: [
          Variable.withString(table),
          Variable.withString(r['id']! as String),
          Variable.withString(r['id']! as String),
          Variable.withString(r['updated_at']! as String),
        ],
        updates: {db.syncOutbox},
      );
    }
    return SyncResult(pushed: found.length);
  }

  Future<void> _dropEntry(String table, String id) => db.customUpdate(
    'DELETE FROM sync_outbox WHERE entity_table = ? AND entity_id = ?',
    variables: [Variable.withString(table), Variable.withString(id)],
    updates: {db.syncOutbox},
  );

  Map<String, Object?> _toRemote(
    TableInfo<Table, dynamic> info,
    String table,
    Map<String, Object?> row,
  ) {
    final json = jsonColumns[table] ?? const {};
    return {
      for (final c in info.$columns)
        c.name: switch (row[c.name]) {
          null => null,
          final Object v when json.contains(c.name) => jsonDecode(v as String),
          final int v when c.type == DriftSqlType.bool => v != 0,
          final Object v => v,
        },
    };
  }

  Future<SyncResult> pull() async {
    var result = const SyncResult();
    for (final table in syncedTableNames) {
      try {
        result += await _pullTable(table);
      } on SyncRemoteException catch (e) {
        result += SyncResult(failed: 1, errorCode: e.code, authPaused: e.auth);
        if (e.auth) return result;
      }
    }
    return result;
  }

  Future<SyncResult> _pullTable(String table) async {
    final cursor = await db
        .customSelect(
          'SELECT cursor_ts FROM local_sync_cursors WHERE table_name = ?',
          variables: [Variable.withString(table)],
        )
        .getSingleOrNull();
    var since = cursor == null
        ? DateTime.utc(1970)
        : DateTime.parse(cursor.read<String>('cursor_ts')).subtract(overlap);
    String? afterId;
    var pulled = 0;
    final info = _table(table);
    while (true) {
      final page = await remote.changedSince(
        table,
        since: since,
        afterId: afterId,
        limit: pullPage,
      );
      if (page.isEmpty) break;
      for (final row in page) {
        if (await _apply(info, table, row)) pulled++;
      }
      final last = page.last;
      since = DateTime.parse(last['server_updated_at']! as String);
      afterId = last['id']! as String;
      await db.customInsert(
        'INSERT INTO local_sync_cursors (table_name, cursor_ts, cursor_id, last_pulled_at) VALUES (?, ?, ?, ?) '
        'ON CONFLICT(table_name) DO UPDATE SET cursor_ts = excluded.cursor_ts, cursor_id = excluded.cursor_id, '
        'last_pulled_at = excluded.last_pulled_at',
        variables: [
          Variable.withString(table),
          Variable.withString(_iso(since)),
          Variable.withString(afterId),
          Variable.withString(_iso(clock.now())),
        ],
        updates: {db.localSyncCursors},
      );
    }
    return SyncResult(pulled: pulled);
  }

  /// Writes a pulled row unless the local copy is newer or waiting to be
  /// pushed. Never creates an outbox entry. Returns whether it was written.
  Future<bool> _apply(
    TableInfo<Table, dynamic> info,
    String table,
    Map<String, Object?> row,
  ) async {
    final id = row['id']! as String;
    final pendingLocal = await db
        .customSelect(
          'SELECT 1 FROM sync_outbox WHERE entity_table = ? AND entity_id = ?',
          variables: [Variable.withString(table), Variable.withString(id)],
        )
        .getSingleOrNull();
    if (pendingLocal != null) return false;
    final remoteUpdated = DateTime.parse(row['updated_at']! as String);
    final local = await db
        .customSelect(
          'SELECT updated_at FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (local != null &&
        !DateTime.parse(local.read<String>('updated_at')).isBefore(remoteUpdated)) {
      return false;
    }

    final natural = localNaturalKeys[table];
    if (natural != null && row[natural] != null) {
      await db.customUpdate(
        'DELETE FROM $table WHERE $natural = ? AND id <> ? '
        'AND NOT EXISTS (SELECT 1 FROM sync_outbox WHERE entity_table = ? AND entity_id = $table.id)',
        variables: [
          Variable.withString('${row[natural]}'),
          Variable.withString(id),
          Variable.withString(table),
        ],
        updates: {info},
      );
    }

    final json = jsonColumns[table] ?? const {};
    final cols = <String>[];
    final vars = <Variable<Object>>[];
    for (final c in info.$columns) {
      if (!row.containsKey(c.name)) continue;
      final v = row[c.name];
      cols.add(c.name);
      vars.add(switch (v) {
        null => const Variable(null),
        _ when json.contains(c.name) => Variable.withString(v is String ? v : jsonEncode(v)),
        final bool b => Variable.withBool(b),
        final String s when c.type == DriftSqlType.dateTime => Variable.withString(
          _iso(DateTime.parse(s)),
        ),
        final int n => Variable.withInt(n),
        final num n => Variable.withInt(n.round()),
        _ => Variable.withString('$v'),
      });
    }
    final updates = [for (final c in cols.where((c) => c != 'id')) '$c = excluded.$c'].join(', ');
    await db.customInsert(
      'INSERT INTO $table (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')}) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      variables: vars,
      updates: {info},
    );
    return true;
  }
}
