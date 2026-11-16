import 'package:drift/drift.dart';

part 'private_database.g.dart';

/// Private database (`fitbuddy_private.db`): everything in PRD §7.1.
///
/// It has its own encryption key and no sync outbox. Nothing under
/// `core/sync`, `core/networking` or any remote source may import this file
/// (enforced by test/architecture). Tables arrive with their features in
/// Phase 5.
@DriftDatabase(tables: [])
class PrivateDatabase extends _$PrivateDatabase {
  PrivateDatabase(super.executor);

  static const databaseName = 'fitbuddy_private';

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
