import 'package:drift/drift.dart';

/// Columns every synced table shares (docs/blueprint/03-database.md §1).
/// Deletes are tombstones: `deletedAt` is set and the row keeps syncing.
mixin SyncedColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
