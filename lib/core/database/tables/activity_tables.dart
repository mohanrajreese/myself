// Drift check constraints refer to the column being defined; this is the
// documented pattern, not a recursive call at run time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../converters.dart';
import 'synced_columns.dart';

const trackingTypeCodes = [
  'boolean',
  'count',
  'numeric',
  'duration',
  'stopwatch',
  'event_log',
  'checklist',
];

/// An ordinary activity the user defined (§5.14). Private activities live in
/// `PrivateDatabase` (decision C5).
@DataClassName('ActivityDefinitionRow')
class ActivityDefinitions extends Table with SyncedColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get category => text()();
  TextColumn get iconKey => text()();
  TextColumn get trackingType => text().check(trackingType.isIn(trackingTypeCodes))();
  TextColumn get priority => text().check(priority.isIn(const ['essential', 'optional']))();

  /// Thousandths of [targetUnit] (count, numeric) or seconds × 1000 (duration).
  IntColumn get targetMilli =>
      integer().nullable().check(targetMilli.isNull() | targetMilli.isBiggerThanValue(0))();
  TextColumn get targetUnit => text().nullable()();

  /// Current schedule rule as JSON (`ScheduleRule`).
  TextColumn get schedule => text()();

  /// JSON list of `{from, rule}`: earlier rules and the day each took effect,
  /// so past days stay "missed" or "not scheduled" after a reschedule.
  TextColumn get scheduleHistory => text().withDefault(const Constant('[]'))();
  BoolColumn get stopwatchEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get showOnDashboard => boolean().withDefault(const Constant(true))();

  /// JSON list of `{id, label}` for checklist activities.
  TextColumn get checklistItems => text().withDefault(const Constant('[]'))();
  TextColumn get status => text().check(status.isIn(const ['active', 'archived']))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get systemKey => text().nullable()();
}

/// One completion or skip. Several per day are allowed; "missed" is derived
/// from the schedule and never stored.
@DataClassName('ActivityLogRow')
@TableIndex(name: 'activity_logs_local_date', columns: {#localDate})
@TableIndex(name: 'activity_logs_definition', columns: {#activityDefinitionId, #localDate})
class ActivityLogs extends Table with SyncedColumns {
  TextColumn get activityDefinitionId => text().references(ActivityDefinitions, #id)();
  TextColumn get status => text().check(status.isIn(const ['completed', 'skipped']))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();

  /// The scheduled time (minutes after midnight) this log answers, if any.
  IntColumn get scheduledSlot =>
      integer().nullable().check(scheduledSlot.isNull() | scheduledSlot.isBetweenValues(0, 1439))();
  IntColumn get countValue =>
      integer().nullable().check(countValue.isNull() | countValue.isBiggerOrEqualValue(0))();
  IntColumn get numericValueMilli => integer().nullable()();
  TextColumn get unit => text().nullable()();
  IntColumn get durationS =>
      integer().nullable().check(durationS.isNull() | durationS.isBetweenValues(0, 86400))();

  /// JSON list of the checklist item ids that were done.
  TextColumn get checklistState => text().nullable()();
  TextColumn get source => text().check(source.isIn(const ['manual', 'notification', 'timer']))();
  TextColumn get notes => text().nullable()();
}

/// A stopwatch or countdown (§5.16). Elapsed time is recomputed from the
/// state and timestamps, never stored as a ticking value. Device-only.
@DataClassName('TimerSessionRow')
class LocalTimerSessions extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text().check(kind.isIn(const ['stopwatch', 'countdown', 'rest']))();
  TextColumn get activityDefinitionId => text().nullable()();
  TextColumn get workoutSessionId => text().nullable()();
  IntColumn get targetDurationS => integer().nullable().check(
    targetDurationS.isNull() | targetDurationS.isBetweenValues(1, 86400),
  )();
  TextColumn get state =>
      text().check(state.isIn(const ['ready', 'running', 'paused', 'completed', 'cancelled']))();

  /// Milliseconds run before [lastResumedAt].
  IntColumn get accumulatedMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastResumedAt => dateTime().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get activityLogId => text().nullable()();
  IntColumn get notificationId => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TimerEventRow')
@TableIndex(name: 'local_timer_events_session', columns: {#sessionId})
class LocalTimerEvents extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(LocalTimerSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get type =>
      text().check(type.isIn(const ['start', 'pause', 'resume', 'finish', 'cancel']))();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
