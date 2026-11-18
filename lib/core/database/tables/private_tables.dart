// Drift check constraints refer to the column being defined; this is the
// documented pattern, not a recursive call at run time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../converters.dart';
import 'activity_tables.dart' show trackingTypeCodes;

/// Columns every private table shares. Never synced: no outbox, no deletedAt.
mixin PrivateColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Private activities and private habit types (§5.12, decision C5).
@DataClassName('PrivateDefinitionRow')
class LocalPrivateActivityDefinitions extends Table with PrivateColumns {
  TextColumn get kind => text().check(kind.isIn(const ['activity', 'habit']))();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get iconKey => text().withDefault(const Constant('lock'))();
  TextColumn get trackingType => text().check(trackingType.isIn(trackingTypeCodes))();
  IntColumn get targetMilli => integer().nullable()();
  TextColumn get targetUnit => text().nullable()();

  /// Schedule rule as JSON; null for habits, which are recorded when they happen.
  TextColumn get schedule => text().nullable()();
  TextColumn get scheduleHistory => text().withDefault(const Constant('[]'))();
  TextColumn get checklistItems => text().withDefault(const Constant('[]'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// `habit.porn`, `habit.masturbation` for the seeded types.
  TextColumn get systemKey => text().nullable()();
}

@DataClassName('PrivateActivityLogRow')
@TableIndex(name: 'local_private_activity_logs_date', columns: {#localDate})
class LocalPrivateActivityLogs extends Table with PrivateColumns {
  TextColumn get definitionId =>
      text().references(LocalPrivateActivityDefinitions, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => text().check(status.isIn(const ['completed', 'skipped']))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  IntColumn get scheduledSlot => integer().nullable()();
  IntColumn get countValue => integer().nullable()();
  IntColumn get numericValueMilli => integer().nullable()();
  IntColumn get durationS => integer().nullable()();
  TextColumn get checklistState => text().nullable()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('PrivateHabitLogRow')
@TableIndex(name: 'local_private_habit_logs_date', columns: {#localDate})
class LocalPrivateHabitLogs extends Table with PrivateColumns {
  TextColumn get definitionId =>
      text().references(LocalPrivateActivityDefinitions, #id, onDelete: KeyAction.cascade)();
  IntColumn get count => integer().check(count.isBetweenValues(1, 100))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  TextColumn get note => text().nullable()();
}

@DataClassName('BowelLogRow')
@TableIndex(name: 'local_bowel_logs_date', columns: {#localDate})
class LocalBowelLogs extends Table with PrivateColumns {
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  IntColumn get count =>
      integer().withDefault(const Constant(1)).check(count.isBetweenValues(1, 20))();
  TextColumn get consistency => text().check(consistency.isIn(const ['hard', 'normal', 'loose']))();
  BoolColumn get straining => boolean().withDefault(const Constant(false))();
  BoolColumn get pain => boolean().nullable()();
  BoolColumn get bleeding => boolean().nullable()();
  TextColumn get notes => text().nullable()();
}

/// Medication and supplements (§5.18). Dosage is the user's own text; the
/// app never interprets it.
@DataClassName('MedicationRow')
class LocalMedications extends Table with PrivateColumns {
  TextColumn get name => text()();
  TextColumn get dosageText => text()();
  TextColumn get schedule => text()();
  BoolColumn get remind => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

@DataClassName('MedicationLogRow')
@TableIndex(name: 'local_medication_logs_med', columns: {#medicationId, #localDate})
class LocalMedicationLogs extends Table with PrivateColumns {
  TextColumn get medicationId =>
      text().references(LocalMedications, #id, onDelete: KeyAction.cascade)();

  /// The scheduled minute this log answers, if any.
  IntColumn get scheduledSlot => integer().nullable()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get status => text().check(status.isIn(const ['taken', 'missed', 'skipped']))();
  DateTimeColumn get actedAt => dateTime()();
  TextColumn get notes => text().nullable()();
}

/// Reminders for private modules. Their text stays here; the scheduler sees
/// only an opaque id and shows a generic title (§3.4 rule 14).
@DataClassName('SensitiveReminderRow')
class LocalSensitiveReminders extends Table with PrivateColumns {
  TextColumn get ownerType =>
      text().check(ownerType.isIn(const ['bowel', 'medication', 'private_activity', 'custom']))();
  TextColumn get ownerId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get schedule => text()();
  TextColumn get quietHoursBehaviour => text().withDefault(const Constant('defer'))();
  IntColumn get snoozeDefaultMin => integer().withDefault(const Constant(10))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}

@DataClassName('ScreenTimeDailyRow')
class LocalScreenTimeDaily extends Table {
  TextColumn get localDate => text().map(const LocalDateConverter())();
  IntColumn get totalMs => integer()();
  BoolColumn get isPartial => boolean().withDefault(const Constant(false))();
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {localDate};
}

@DataClassName('ScreenTimeAppRow')
class LocalScreenTimeApps extends Table {
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get packageName => text()();
  TextColumn get appLabel => text()();
  IntColumn get foregroundMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {localDate, packageName};
}

/// Index of encrypted progress photo files (§5.3, C2).
@DataClassName('ProgressPhotoRow')
class LocalProgressPhotos extends Table with PrivateColumns {
  DateTimeColumn get takenAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get fileName => text()();
  TextColumn get note => text().nullable()();
}
