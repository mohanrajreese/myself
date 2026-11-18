import 'package:drift/drift.dart';

import '../converters.dart';

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

/// Read-only reference foods bundled with the app (decision D3). Values are
/// per [servingLabel] as published by [source]. Never synced.
@DataClassName('CatalogueFoodRow')
@TableIndex(name: 'local_food_catalogue_name', columns: {#name})
class LocalFoodCatalogue extends Table {
  /// `<source>:<id in the source dataset>`.
  TextColumn get id => text()();
  TextColumn get source => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get servingLabel => text()();
  IntColumn get servingWeightMg => integer()();
  IntColumn get energyKcalMilli => integer()();
  IntColumn get proteinMg => integer()();
  IntColumn get carbsMg => integer()();
  IntColumn get fatMg => integer()();
  IntColumn get fibreMg => integer()();

  /// True for values calculated from a recipe rather than measured.
  BoolColumn get isEstimate => boolean().withDefault(const Constant(false))();

  /// A household serving as published, for example "1 idli", and its weight.
  TextColumn get householdLabel => text().nullable()();
  IntColumn get householdWeightMg => integer().nullable()();

  /// True when the stated energy contradicts the macronutrients in the source.
  BoolColumn get hasConflict => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Index of encrypted meal photo files kept in app storage. Never synced.
@DataClassName('MealPhotoRow')
class LocalMealPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get mealLogId => text()();
  TextColumn get fileName => text()();
  DateTimeColumn get takenAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Rest days, soreness and recovery ratings (§5.19, decision C4). Device-only.
@DataClassName('RecoveryLogRow')
class LocalRecoveryLogs extends Table {
  TextColumn get localDate => text().map(const LocalDateConverter())();
  BoolColumn get isRestDay => boolean().withDefault(const Constant(false))();
  IntColumn get soreness => integer().nullable()();
  IntColumn get recovery => integer().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {localDate};
}
