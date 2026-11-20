import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

final _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// Throws unless [key] is exactly 64 lower-case hex digits. The key is placed
/// inside a PRAGMA statement, so its shape is checked before use.
void validateHexKey(String key) {
  if (!_hexKey.hasMatch(key)) {
    throw ArgumentError('Database key must be 64 lower-case hex digits');
  }
}

/// Unlocks an encrypted connection. Runs before Drift touches the database.
///
/// Fails loudly when the SQLite build has no cipher support, so an
/// unencrypted database can never be created by mistake.
void configureEncryption(CommonDatabase database, String hexKey) {
  validateHexKey(hexKey);
  if (database.select('PRAGMA cipher').isEmpty) {
    throw StateError('SQLite was built without encryption support');
  }
  database
    ..execute("PRAGMA cipher = 'sqlcipher'")
    ..execute('PRAGMA key = "x\'$hexKey\'"')
    // Reading the schema proves the key is right; a wrong key fails here.
    ..select('SELECT count(*) FROM sqlite_master')
    ..execute('PRAGMA journal_mode = WAL')
    ..execute('PRAGMA busy_timeout = 5000')
    ..execute('PRAGMA foreign_keys = ON');
}

/// Opens an encrypted database file in app storage. One shared connection
/// serves every isolate, so there is a single writer.
QueryExecutor openEncryptedDatabase({required String name, required String hexKey}) {
  validateHexKey(hexKey);
  return driftDatabase(
    name: name,
    native: DriftNativeOptions(
      shareAcrossIsolates: true,
      setup: (database) => configureEncryption(database, hexKey),
    ),
  );
}
