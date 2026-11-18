import 'package:drift/drift.dart';

import '../utils/local_date.dart';
import 'converters.dart';
import 'tables/activity_tables.dart' show trackingTypeCodes;
import 'tables/private_tables.dart';

part 'private_database.g.dart';

/// Private database (`fitbuddy_private.db`): everything in PRD §7.1.
///
/// It has its own encryption key and no sync outbox. Nothing under
/// `core/sync`, `core/networking` or any remote source may import this file
/// (enforced by test/architecture).
@DriftDatabase(
  tables: [
    LocalPrivateActivityDefinitions,
    LocalPrivateActivityLogs,
    LocalPrivateHabitLogs,
    LocalBowelLogs,
    LocalMedications,
    LocalMedicationLogs,
    LocalSensitiveReminders,
    LocalScreenTimeDaily,
    LocalScreenTimeApps,
    LocalProgressPhotos,
  ],
)
class PrivateDatabase extends _$PrivateDatabase {
  PrivateDatabase(super.executor);

  static const databaseName = 'fitbuddy_private';

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        // Phase 5: every private table (version 1 had none).
        await migrator.createAll();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
