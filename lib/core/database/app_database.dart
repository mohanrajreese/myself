import 'package:drift/drift.dart';

import '../utils/local_date.dart';
import 'converters.dart';
import 'synced_tables.dart';
import 'tables/activity_tables.dart';
import 'tables/finance_tables.dart';
import 'tables/fitness_tables.dart';
import 'tables/local_tables.dart';
import 'tables/profile_tables.dart';
import 'tables/tracking_tables.dart';

part 'app_database.g.dart';

/// Main database (`fitbuddy.db`): synced tables and local operational tables.
/// Private records live in `PrivateDatabase`, which sync code cannot import.
@DriftDatabase(
  tables: [
    Profiles,
    UserGoals,
    NutritionGoals,
    WeightLogs,
    SyncOutbox,
    LocalAppSettings,
    BodyMeasurements,
    WaterLogs,
    FoodItems,
    MealLogs,
    MealFoodItems,
    SavedMeals,
    SleepLogs,
    DailyHealthCheckins,
    LocalFoodCatalogue,
    LocalMealPhotos,
    ActivityDefinitions,
    ActivityLogs,
    LocalTimerSessions,
    LocalTimerEvents,
    Reminders,
    LocalNotificationState,
    StepLogs,
    Exercises,
    WorkoutSessions,
    WorkoutExercises,
    ExerciseSets,
    WorkoutTemplates,
    LocalStepReadings,
    LocalStepDaily,
    LocalWorkoutRoutePoints,
    LocalRecoveryLogs,
    LocalSyncCursors,
    FinanceCategories,
    Debts,
    DebtPayments,
    RecurringExpenses,
    Expenses,
    Budgets,
    LocalExpenseReceipts,
    LoanChanges,
    InstalmentSkips,
    CardStatements,
    Incomes,
    ExpenseSplits,
    LocalBudgetAlerts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const databaseName = 'fitbuddy';

  static const _version5Indexes = {
    'activity_logs_local_date',
    'activity_logs_definition',
    'local_timer_events_session',
  };

  static const _version6Indexes = {
    'local_notification_state_reminder',
    'local_notification_state_at',
  };

  static const _version10Indexes = {'debt_payments_debt', 'expenses_local_date', 'expenses_meal'};

  static const _version11Indexes = {
    'loan_changes_debt',
    'instalment_skips_debt',
    'card_statements_debt',
    'incomes_local_date',
    'expense_splits_expense',
  };

  static const _version7Indexes = {
    'workout_sessions_local_date',
    'workout_exercises_session',
    'exercise_sets_workout_exercise',
    'local_step_readings_time',
    'local_workout_route_points_session',
  };

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        // Phase 2: body measurements, water, nutrition, sleep, wellness.
        for (final table in <TableInfo<Table, Object?>>[
          bodyMeasurements,
          waterLogs,
          foodItems,
          mealLogs,
          mealFoodItems,
          savedMeals,
          sleepLogs,
          dailyHealthCheckins,
        ]) {
          await migrator.createTable(table);
        }
        for (final index in allSchemaEntities.whereType<Index>()) {
          const notInVersion2 = {
            'weight_logs_local_date',
            'local_food_catalogue_name',
            ..._version5Indexes,
            ..._version6Indexes,
            ..._version7Indexes,
            ..._version10Indexes,
            ..._version11Indexes,
          };
          if (!notInVersion2.contains(index.entityName)) await migrator.create(index);
        }
      }
      if (from < 3) {
        // Bundled food catalogue and the meal photo index.
        await migrator.createTable(localFoodCatalogue);
        await migrator.createTable(localMealPhotos);
        await migrator.create(
          allSchemaEntities.whereType<Index>().firstWhere(
            (index) => index.entityName == 'local_food_catalogue_name',
          ),
        );
      }
      if (from < 4) {
        // Household servings and conflict flag on the catalogue; link from
        // the user's edited copy of a catalogue food.
        // Tables created by an earlier step of this same upgrade already have
        // these columns; only add them to tables that existed before.
        if (from >= 3) {
          await migrator.addColumn(localFoodCatalogue, localFoodCatalogue.householdLabel);
          await migrator.addColumn(localFoodCatalogue, localFoodCatalogue.householdWeightMg);
          await migrator.addColumn(localFoodCatalogue, localFoodCatalogue.hasConflict);
        }
        if (from >= 2) await migrator.addColumn(foodItems, foodItems.catalogueRef);
      }
      if (from < 5) {
        // Phase 3: activities, their logs, and device-only timers.
        for (final table in <TableInfo<Table, Object?>>[
          activityDefinitions,
          activityLogs,
          localTimerSessions,
          localTimerEvents,
        ]) {
          await migrator.createTable(table);
        }
        for (final index in allSchemaEntities.whereType<Index>()) {
          if (_version5Indexes.contains(index.entityName)) await migrator.create(index);
        }
      }
      if (from < 6) {
        // Phase 3: reminders and notification state.
        await migrator.createTable(reminders);
        await migrator.createTable(localNotificationState);
        for (final index in allSchemaEntities.whereType<Index>()) {
          if (_version6Indexes.contains(index.entityName)) await migrator.create(index);
        }
      }
      if (from < 7) {
        // Phase 4: steps, exercises, workouts, templates, GPS routes.
        for (final table in <TableInfo<Table, Object?>>[
          stepLogs,
          exercises,
          workoutSessions,
          workoutExercises,
          exerciseSets,
          workoutTemplates,
          localStepReadings,
          localStepDaily,
          localWorkoutRoutePoints,
        ]) {
          await migrator.createTable(table);
        }
        for (final index in allSchemaEntities.whereType<Index>()) {
          if (_version7Indexes.contains(index.entityName)) await migrator.create(index);
        }
      }
      if (from < 8) {
        // Phase 5: rest days and recovery ratings (device-only, C4).
        await migrator.createTable(localRecoveryLogs);
      }
      if (from < 9) {
        // Phase 6: pull cursors for the sync engine.
        await migrator.createTable(localSyncCursors);
      }
      if (from < 10) {
        // Phase 8: money (PRD §5.21).
        for (final table in <TableInfo<Table, Object?>>[
          financeCategories,
          debts,
          debtPayments,
          recurringExpenses,
          expenses,
          budgets,
          localExpenseReceipts,
        ]) {
          await migrator.createTable(table);
        }
        for (final index in allSchemaEntities.whereType<Index>()) {
          if (_version10Indexes.contains(index.entityName)) await migrator.create(index);
        }
      }
      if (from < 11) {
        // Phase 9: money additions (PRD §5.22).
        // Tables created at v10 already have the v11 columns when the
        // database is created fresh, so only add them on a real upgrade.
        if (from == 10) {
          await migrator.addColumn(financeCategories, financeCategories.kind);
          await migrator.addColumn(debts, debts.creditLimitPaise);
          await migrator.addColumn(debts, debts.statementDay);
          await migrator.addColumn(debts, debts.cardDueDay);
          await migrator.addColumn(debts, debts.dueRemind);
          await migrator.addColumn(debts, debts.dueRemindDays);
          await migrator.addColumn(recurringExpenses, recurringExpenses.kind);
          await migrator.addColumn(expenses, expenses.cardDebtId);
        }
        for (final table in <TableInfo<Table, Object?>>[
          loanChanges,
          instalmentSkips,
          cardStatements,
          incomes,
          expenseSplits,
          localBudgetAlerts,
        ]) {
          await migrator.createTable(table);
        }
        for (final index in allSchemaEntities.whereType<Index>()) {
          if (_version11Indexes.contains(index.entityName)) await migrator.create(index);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _installOutboxAllowList();
    },
  );

  /// Removes every row from every table (used when the device is handed to
  /// a different account; call C11).
  Future<void> eraseAllData() => transaction(() async {
    await customStatement('PRAGMA defer_foreign_keys = ON');
    for (final table in allTables) {
      await delete(table).go();
    }
  });

  /// Rebuilt on every open so it always matches [syncedTableNames].
  Future<void> _installOutboxAllowList() async {
    final allowed = syncedTableNames.map((name) => "'$name'").join(', ');
    for (final event in const ['INSERT', 'UPDATE OF entity_table']) {
      final name = 'sync_outbox_allowlist_${event.split(' ').first.toLowerCase()}';
      await customStatement('DROP TRIGGER IF EXISTS $name');
      await customStatement(
        'CREATE TRIGGER $name BEFORE $event ON sync_outbox '
        'WHEN NEW.entity_table NOT IN ($allowed) '
        "BEGIN SELECT RAISE(ABORT, 'table is not syncable'); END",
      );
    }
  }
}
