// Drift check constraints refer to the column being defined; this is the
// documented pattern, not a recursive call at run time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../converters.dart';
import 'synced_columns.dart';

const mealCategoryCodes = [
  'early_morning',
  'breakfast',
  'mid_morning',
  'lunch',
  'evening_snack',
  'dinner',
  'late_night',
  'other',
];

const junkCategoryCodes = ['fast_food', 'fried_snacks', 'sweets', 'sugary_drinks', 'packaged_snacks', 'other'];

@DataClassName('BodyMeasurementRow')
@TableIndex(name: 'body_measurements_type_date', columns: {#measurementType, #localDate})
class BodyMeasurements extends Table with SyncedColumns {
  /// Built-in key (`waist`, `chest`, …) or `custom:<name>`.
  TextColumn get measurementType => text()();

  /// Thousandths of [unit]: 86.5 cm is 86500.
  IntColumn get valueMilli => integer().check(valueMilli.isBiggerThanValue(0))();
  TextColumn get unit => text().check(unit.isIn(const ['cm', 'percent']))();
  TextColumn get entryUnit => text().check(entryUnit.isIn(const ['cm', 'in', 'percent']))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('WaterLogRow')
@TableIndex(name: 'water_logs_local_date', columns: {#localDate})
class WaterLogs extends Table with SyncedColumns {
  IntColumn get amountMl => integer().check(amountMl.isBetweenValues(1, 5000))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
}

@DataClassName('FoodItemRow')
@TableIndex(name: 'food_items_name', columns: {#name})
class FoodItems extends Table with SyncedColumns {
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('other'))();
  TextColumn get servingLabel => text()();
  IntColumn get servingQtyMilli => integer().check(servingQtyMilli.isBiggerThanValue(0))();
  TextColumn get servingUnit => text()();
  IntColumn get servingWeightMg => integer().nullable()();
  IntColumn get energyKcalMilli => integer().check(energyKcalMilli.isBiggerOrEqualValue(0))();
  IntColumn get proteinMg => integer().check(proteinMg.isBiggerOrEqualValue(0))();
  IntColumn get carbsMg => integer().check(carbsMg.isBiggerOrEqualValue(0))();
  IntColumn get fatMg => integer().check(fatMg.isBiggerOrEqualValue(0))();
  IntColumn get fibreMg => integer().check(fibreMg.isBiggerOrEqualValue(0))();
  TextColumn get junkCategory =>
      text().nullable().check(junkCategory.isNull() | junkCategory.isIn(junkCategoryCodes))();
  BoolColumn get isSaved => boolean().withDefault(const Constant(false))();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  /// Set when this food is the user's edited copy of a catalogue food
  /// (`<source>:<id>`). The catalogue original is then hidden from search.
  TextColumn get catalogueRef => text().nullable()();
}

@DataClassName('MealLogRow')
@TableIndex(name: 'meal_logs_local_date', columns: {#localDate})
class MealLogs extends Table with SyncedColumns {
  TextColumn get mealCategory => text().check(mealCategory.isIn(mealCategoryCodes))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  TextColumn get notes => text().nullable()();
  BoolColumn get hasPhoto => boolean().withDefault(const Constant(false))();
}

/// One food in a meal. Nutrition values are a snapshot of the totals for the
/// quantity eaten, so later edits to the food never change past meals.
@DataClassName('MealFoodItemRow')
@TableIndex(name: 'meal_food_items_meal', columns: {#mealLogId})
class MealFoodItems extends Table with SyncedColumns {
  TextColumn get mealLogId => text().references(MealLogs, #id)();
  TextColumn get foodItemId => text().nullable().references(FoodItems, #id, onDelete: KeyAction.setNull)();
  TextColumn get foodName => text()();
  IntColumn get quantityMilli => integer().check(quantityMilli.isBiggerThanValue(0))();
  TextColumn get unit => text()();
  IntColumn get servingWeightMg => integer().nullable()();
  IntColumn get energyKcalMilli => integer().check(energyKcalMilli.isBiggerOrEqualValue(0))();
  IntColumn get proteinMg => integer().check(proteinMg.isBiggerOrEqualValue(0))();
  IntColumn get carbsMg => integer().check(carbsMg.isBiggerOrEqualValue(0))();
  IntColumn get fatMg => integer().check(fatMg.isBiggerOrEqualValue(0))();
  IntColumn get fibreMg => integer().check(fibreMg.isBiggerOrEqualValue(0))();
  TextColumn get junkCategory =>
      text().nullable().check(junkCategory.isNull() | junkCategory.isIn(junkCategoryCodes))();
  TextColumn get itemNotes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('SavedMealRow')
class SavedMeals extends Table with SyncedColumns {
  TextColumn get name => text()();
  TextColumn get mealCategory =>
      text().nullable().check(mealCategory.isNull() | mealCategory.isIn(mealCategoryCodes))();

  /// JSON list of item snapshots.
  TextColumn get items => text()();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
}

@DataClassName('SleepLogRow')
@TableIndex(name: 'sleep_logs_local_date', columns: {#localDate})
class SleepLogs extends Table with SyncedColumns {
  TextColumn get kind => text().check(kind.isIn(const ['night', 'nap']))();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  IntColumn get durationS => integer().check(durationS.isBetweenValues(60, 86400))();
  IntColumn get quality => integer().nullable().check(quality.isBetweenValues(1, 5))();
  TextColumn get notes => text().nullable()();

  /// The day the user woke up, so an overnight sleep belongs to one day.
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
}

@DataClassName('HealthCheckinRow')
@TableIndex(name: 'daily_health_checkins_local_date', columns: {#localDate})
class DailyHealthCheckins extends Table with SyncedColumns {
  IntColumn get energy => integer().check(energy.isBetweenValues(1, 5))();
  IntColumn get mood => integer().check(mood.isBetweenValues(1, 5))();
  IntColumn get stress => integer().check(stress.isBetweenValues(1, 5))();
  IntColumn get wellness => integer().check(wellness.isBetweenValues(1, 5))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  TextColumn get notes => text().nullable()();
}
