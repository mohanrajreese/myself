import 'package:drift/drift.dart';

/// Pending uploads: one entry per changed row. The payload is read from the
/// row itself when it is sent. A trigger (see `AppDatabase`) restricts
/// `entityTable` to the synced tables.
class SyncOutbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get enqueuedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn get lastErrorCode => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {entityTable, entityId},
  ];
}

/// Device-only settings (dashboard layout, bound account, drafts, …).
class LocalAppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
