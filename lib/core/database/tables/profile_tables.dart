// Drift check constraints refer to the column being defined; this is the
// documented pattern, not a recursive call at run time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../converters.dart';
import 'synced_columns.dart';

class Profiles extends Table with SyncedColumns {
  TextColumn get displayName => text()();
  TextColumn get dateOfBirth => text().map(const LocalDateConverter()).nullable()();
  IntColumn get heightMm => integer().nullable().check(heightMm.isBetweenValues(300, 3000))();
  TextColumn get weightUnit => text().check(weightUnit.isIn(const ['kg', 'lb']))();
  TextColumn get lengthUnit => text().check(lengthUnit.isIn(const ['cm', 'in']))();
  TextColumn get volumeUnit => text().check(volumeUnit.isIn(const ['ml', 'fl_oz']))();
  TextColumn get distanceUnit => text().check(distanceUnit.isIn(const ['km', 'mi']))();
  TextColumn get timezone => text()();

  /// `HH:mm`, 24-hour.
  TextColumn get wakeTime => text().nullable()();

  /// JSON list of ISO weekdays (1 = Monday).
  TextColumn get workoutDays => text().withDefault(const Constant('[]'))();
  TextColumn get customMeasurementTypes => text().withDefault(const Constant('[]'))();
  DateTimeColumn get onboardingCompletedAt => dateTime().nullable()();
}

/// One row per change. The row in force on a day is the latest one whose
/// `effectiveFrom` is on or before that day, so history is never rewritten
/// when a goal changes (PRD §5.1).
class UserGoals extends Table with SyncedColumns {
  TextColumn get effectiveFrom => text().map(const LocalDateConverter())();
  IntColumn get targetWeightG => integer().nullable().check(targetWeightG.isBiggerThanValue(0))();
  IntColumn get dailySteps => integer().nullable().check(dailySteps.isBiggerOrEqualValue(0))();
  IntColumn get dailyWaterMl => integer().nullable().check(dailyWaterMl.isBiggerOrEqualValue(0))();
  IntColumn get sleepTargetMin =>
      integer().nullable().check(sleepTargetMin.isBetweenValues(0, 1440))();

  /// JSON list of text.
  TextColumn get fitnessGoals => text().withDefault(const Constant('[]'))();
}

class NutritionGoals extends Table with SyncedColumns {
  TextColumn get effectiveFrom => text().map(const LocalDateConverter())();
  IntColumn get energyKcalMilli =>
      integer().nullable().check(energyKcalMilli.isBiggerOrEqualValue(0))();
  IntColumn get proteinMg => integer().nullable().check(proteinMg.isBiggerOrEqualValue(0))();
  IntColumn get carbsMg => integer().nullable().check(carbsMg.isBiggerOrEqualValue(0))();
  IntColumn get fatMg => integer().nullable().check(fatMg.isBiggerOrEqualValue(0))();
  IntColumn get fibreMg => integer().nullable().check(fibreMg.isBiggerOrEqualValue(0))();
}

@TableIndex(name: 'weight_logs_local_date', columns: {#localDate})
class WeightLogs extends Table with SyncedColumns {
  IntColumn get weightG => integer().check(weightG.isBetweenValues(1000, 700000))();
  TextColumn get entryUnit => text().check(entryUnit.isIn(const ['kg', 'lb']))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  TextColumn get notes => text().nullable()();
}
