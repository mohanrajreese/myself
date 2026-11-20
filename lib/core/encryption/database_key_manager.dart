import 'dart:math';

import '../errors/failure.dart';
import '../errors/result.dart';
import 'secret_store.dart';

enum DatabaseId {
  app('db_key_app'),
  private('db_key_private'),

  /// Encrypts photo files kept in app storage.
  files('file_key');

  const DatabaseId(this.storageKey);
  final String storageKey;
}

/// Creates and keeps one random 256-bit key per database.
///
/// A stored key that is missing is created; a stored key that is damaged is
/// reported and left alone, because replacing it would silently orphan the
/// database it encrypts.
final class DatabaseKeyManager {
  DatabaseKeyManager(this._store, {Random? random}) : _random = random ?? Random.secure();

  final SecretStore _store;
  final Random _random;

  static final _hexKey = RegExp(r'^[0-9a-f]{64}$');

  Future<Result<String>> keyFor(DatabaseId id) async {
    try {
      final existing = await _store.read(id.storageKey);
      if (existing != null) {
        return _hexKey.hasMatch(existing)
            ? Ok(existing)
            : const Err(StorageFailure('database_key_corrupt'));
      }
      final created = _newKey();
      await _store.write(id.storageKey, created);
      return Ok(created);
    } on Object {
      return const Err(StorageFailure('database_key_unavailable'));
    }
  }

  /// Makes both databases permanently unreadable (used by "delete all data").
  Future<void> destroyAll() async {
    for (final id in DatabaseId.values) {
      await _store.delete(id.storageKey);
    }
  }

  String _newKey() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
