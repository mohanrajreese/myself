import 'package:drift/drift.dart';

import 'app_database.dart';

extension OutboxWriter on AppDatabase {
  /// Marks one row as needing upload. Call inside the same transaction as the
  /// row write. A row has at most one entry; changing it again resets the
  /// retry state. The table name is checked by a database trigger.
  Future<void> enqueueForSync(String table, String id, DateTime now) {
    final stamp = now.toUtc().toIso8601String();
    return customInsert(
      'INSERT INTO sync_outbox (entity_table, entity_id, enqueued_at, attempts, next_attempt_at, last_error_code) '
      'VALUES (?1, ?2, ?3, 0, ?3, NULL) '
      'ON CONFLICT (entity_table, entity_id) DO UPDATE SET '
      'enqueued_at = excluded.enqueued_at, attempts = 0, '
      'next_attempt_at = excluded.next_attempt_at, last_error_code = NULL',
      variables: [Variable.withString(table), Variable.withString(id), Variable.withString(stamp)],
      updates: {syncOutbox},
    );
  }
}
