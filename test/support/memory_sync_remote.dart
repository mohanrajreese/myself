import 'package:fitbuddy/core/sync/sync_remote.dart';

/// In-memory stand-in for Supabase: upserts by id (or the given conflict
/// key), stamps `server_updated_at` from [clock], pages by (stamp, id).
class MemorySyncRemote implements SyncRemote {
  MemorySyncRemote({required this.clock});
  final DateTime Function() clock;
  final Map<String, Map<String, Map<String, Object?>>> _tables = {};
  final Map<String, String?> conflictKeys = {};
  SyncRemoteException? failNext;
  Future<void> Function()? beforeUpsert;
  int pageSize = 500;
  int upserts = 0;
  var _tick = 1;

  /// Every table name written to, for privacy checks.
  Iterable<String> get tableNames => _tables.keys;

  List<Map<String, Object?>> rows(String table) => [...?_tables[table]?.values];

  void seed(String table, List<Map<String, Object?>> rows) {
    for (final r in rows) {
      (_tables[table] ??= {})[r['id']! as String] = {...r, 'server_updated_at': _stamp()};
    }
  }

  String _stamp() => clock().toUtc().add(Duration(microseconds: _tick++)).toIso8601String();

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows, {String? onConflict}) async {
    final hook = beforeUpsert;
    beforeUpsert = null;
    if (hook != null) await hook();
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    upserts++;
    conflictKeys[table] = onConflict;
    for (final r in rows) {
      (_tables[table] ??= {})[r['id']! as String] = {...r, 'user_id': 'user-1', 'server_updated_at': _stamp()};
    }
  }

  @override
  Future<List<Map<String, Object?>>> changedSince(
    String table, {
    required DateTime since,
    String? afterId,
    required int limit,
  }) async {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    final s = since.toUtc();
    final all = rows(table)
      ..sort((a, b) {
        final c = DateTime.parse(
          a['server_updated_at']! as String,
        ).compareTo(DateTime.parse(b['server_updated_at']! as String));
        return c != 0 ? c : (a['id']! as String).compareTo(b['id']! as String);
      });
    return all
        .where((r) {
          final t = DateTime.parse(r['server_updated_at']! as String);
          if (afterId == null) return !t.isBefore(s);
          return t.isAfter(s) || (t == s && (r['id']! as String).compareTo(afterId) > 0);
        })
        .take(limit < pageSize ? limit : pageSize)
        .toList();
  }

  @override
  Future<void> deleteAccount() async => _tables.clear();

  final List<String> statusReports = [];

  @override
  Future<void> reportStatus({
    required String deviceId,
    required DateTime syncedAt,
    required int schemaVersion,
    required String appVersion,
  }) async => statusReports.add(deviceId);
}
