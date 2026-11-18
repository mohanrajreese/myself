/// The cloud side of sync (03-database.md §6). Implemented with Supabase;
/// tests use an in-memory version. Never given private data.
abstract interface class SyncRemote {
  /// Inserts or updates [rows] in [table]. [onConflict] names the unique key
  /// when it is not `id` (step totals use `user_id,log_date`).
  Future<void> upsert(String table, List<Map<String, Object?>> rows, {String? onConflict});

  /// Rows changed at or after [since] (or, with [afterId], after the
  /// position `(since, afterId)`), ordered by `(server_updated_at, id)`.
  Future<List<Map<String, Object?>>> changedSince(
    String table, {
    required DateTime since,
    String? afterId,
    required int limit,
  });

  /// Deletes the signed-in account and every synced row (Edge Function).
  Future<void> deleteAccount();
}

/// A failed remote call. [code] is a short identifier safe to store and
/// show; it never contains a payload.
final class SyncRemoteException implements Exception {
  const SyncRemoteException(this.code, {this.auth = false});
  final String code;

  /// The session is missing or expired; sync pauses until sign-in.
  final bool auth;

  @override
  String toString() => 'SyncRemoteException($code)';
}
