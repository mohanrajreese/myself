import 'dart:convert';

import '../utils/clock.dart';
import 'app_database.dart';

/// Device-only key-value settings, stored as JSON in the encrypted main
/// database. Never synced.
final class SettingsRepository {
  SettingsRepository(this._db, {required Clock clock}) : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  Future<Object?> read(String key) async {
    final row = await (_db.select(
      _db.localAppSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.valueJson);
  }

  Stream<Object?> watch(String key) =>
      (_db.select(_db.localAppSettings)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : jsonDecode(row.valueJson))
          .distinct((a, b) => jsonEncode(a) == jsonEncode(b));

  Future<void> write(String key, Object value) => _db
      .into(_db.localAppSettings)
      .insertOnConflictUpdate(
        LocalAppSettingsCompanion.insert(
          key: key,
          valueJson: jsonEncode(value),
          updatedAt: _clock.now().toUtc(),
        ),
      );

  Future<void> remove(String key) =>
      (_db.delete(_db.localAppSettings)..where((t) => t.key.equals(key))).go();
}
