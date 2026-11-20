import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_remote.dart';

/// [SyncRemote] over PostgREST. Row Level Security limits every call to the
/// signed-in user's rows (03-database.md §5.4).
final class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);
  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 30);

  Future<T> _guard<T>(Future<T> Function() call) async {
    if (_client.auth.currentSession == null) {
      throw const SyncRemoteException('signed_out', auth: true);
    }
    try {
      return await call().timeout(_timeout);
    } on AuthException {
      throw const SyncRemoteException('auth', auth: true);
    } on PostgrestException catch (e) {
      final auth = e.code == 'PGRST301' || e.code == '401' || e.code == '42501';
      throw SyncRemoteException('server_${e.code ?? 'unknown'}', auth: auth);
    } on FunctionException catch (e) {
      throw SyncRemoteException('function_${e.status}', auth: e.status == 401);
    } on SocketException {
      throw const SyncRemoteException('network');
    } on TimeoutException {
      throw const SyncRemoteException('timeout');
    } on HttpException {
      throw const SyncRemoteException('network');
    }
  }

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows, {String? onConflict}) =>
      _guard(() => _client.from(table).upsert(rows, onConflict: onConflict));

  @override
  Future<List<Map<String, Object?>>> changedSince(
    String table, {
    required DateTime since,
    String? afterId,
    required int limit,
  }) => _guard(() async {
    final ts = since.toUtc().toIso8601String();
    final base = _client.from(table).select();
    final filtered = afterId == null
        ? base.gte('server_updated_at', ts)
        : base.or('server_updated_at.gt.$ts,and(server_updated_at.eq.$ts,id.gt.$afterId)');
    final rows = await filtered
        .order('server_updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
    return [for (final r in rows) Map<String, Object?>.from(r)];
  });

  @override
  Future<void> deleteAccount() =>
      _guard(() => _client.functions.invoke('delete-account', method: HttpMethod.post));

  @override
  Future<void> reportStatus({
    required String deviceId,
    required DateTime syncedAt,
    required int schemaVersion,
    required String appVersion,
  }) => _guard(() async {
    final at = syncedAt.toUtc().toIso8601String();
    await _client.from('cloud_sync_metadata').upsert({
      'device_id': deviceId,
      'last_push_at': at,
      'last_pull_at': at,
      'schema_version': schemaVersion,
      'app_version': appVersion,
      'updated_at': at,
    });
  });
}
