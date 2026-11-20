import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/widgets/fb_states.dart';
import '../core/widgets/l10n.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/dashboard/presentation/customise_home_screen.dart';
import '../features/onboarding/application/setup_controller.dart';
import '../features/activities/presentation/activity_detail_screen.dart';
import '../features/activities/presentation/activity_editor_screen.dart';
import '../features/body_measurements/presentation/measurement_screens.dart';
import '../features/reminders/presentation/notification_screens.dart';
import '../features/reminders/presentation/reminder_editor_screen.dart';
import '../features/timers/presentation/timer_screen.dart';
import '../features/dashboard/presentation/home_screen.dart';
import '../features/food_database/presentation/food_screens.dart';
import '../features/health_hub/presentation/health_screen.dart';
import '../features/nutrition/domain/meals.dart';
import '../features/nutrition/presentation/meal_form_screen.dart';
import '../features/nutrition/presentation/nutrition_screens.dart';
import '../features/settings/presentation/about_screen.dart';
import '../features/sleep/presentation/sleep_screens.dart';
import '../features/water/presentation/water_screens.dart';
import '../features/weight/presentation/weight_screen.dart';
import '../features/wellness/presentation/wellness_screens.dart';
import '../features/onboarding/presentation/edit_setup_screen.dart';
import '../features/onboarding/presentation/onboarding_screens.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/weight/presentation/add_weight_sheet.dart';
import '../features/medication/presentation/medication_screens.dart';
import '../features/private_space/presentation/lock_screens.dart';
import '../features/private_space/presentation/private_space_screens.dart';
import '../features/recovery/presentation/recovery_screen.dart';
import '../features/screen_time/presentation/screen_time_screen.dart';
import 'routine/hygiene_screen.dart';
import '../features/settings/presentation/account_sync_screen.dart';
import '../features/settings/presentation/data_screens.dart';
import '../features/insights/domain/report.dart';
import '../features/insights/presentation/insights_screens.dart';
import '../features/money/presentation/money_screens.dart';
import '../features/private_space/presentation/private_report_screen.dart';
import 'app_shell.dart';
import 'sync_controller.dart';
import 'providers.dart';
import '../features/fitness/domain/workouts.dart';
import '../features/fitness/presentation/cardio_screens.dart';
import '../features/fitness/presentation/fitness_screen.dart';
import '../features/fitness/presentation/gym_screens.dart';
import '../features/fitness/presentation/history_screens.dart';
import '../features/fitness/presentation/steps_screens.dart';
import 'routes.dart';
import 'routine/habits_screen.dart';

/// Whether the signed-in account still has to go through onboarding.
final setupStatusProvider = Provider<SetupStatus>((ref) {
  final account = ref.watch(currentAccountProvider);
  if (account == null) return SetupStatus.unknown;
  // A returning user's records are downloading: decide only once they are in.
  if (ref.watch(syncControllerProvider).phase == SyncPhase.restoring) return SetupStatus.unknown;
  return ref
      .watch(profileProvider(account.id))
      .when(
        data: (profile) =>
            profile?.onboardingCompleted == true ? SetupStatus.complete : SetupStatus.needed,
        loading: () => SetupStatus.unknown,
        error: (_, _) => SetupStatus.needed,
      );
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..listen(setupStatusProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) async {
      final target = resolveRedirect(
        sessionActive: ref.read(sessionControllerProvider).active,
        setup: ref.read(setupStatusProvider),
        location: state.matchedLocation,
      );
      if (target != Routes.onboardingProfile) return target;
      // Entering onboarding: reopen the step the user had reached.
      final saved = await ref.read(settingsRepositoryProvider).read(SetupKeys.resumePath);
      return Routes.onboardingSteps.contains(saved) ? saved! as String : target;
    },
    routes: [
      GoRoute(
        path: Routes.loading,
        builder: (context, state) => Scaffold(body: FbLoading(semanticLabel: context.l10n.loading)),
      ),
      GoRoute(path: Routes.signIn, builder: (context, state) => const SignInScreen()),
      for (final step in OnboardingStep.values)
        GoRoute(
          path: Routes.onboardingSteps[step.index],
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: OnboardingScreen(key: ValueKey(step), step: step),
          ),
        ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (context, state) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.fitness,
                builder: (context, state) => const FitnessScreen(),
                routes: [
                  GoRoute(path: 'steps', builder: (context, state) => const StepsScreen()),
                  GoRoute(
                    path: 'history',
                    builder: (context, state) => const WorkoutHistoryScreen(),
                  ),
                  GoRoute(
                    path: 'records',
                    builder: (context, state) => const PersonalRecordsScreen(),
                  ),
                  GoRoute(
                    path: 'exercises',
                    builder: (context, state) => const ExerciseLibraryScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.nutrition,
                builder: (context, state) => const DiaryScreen(),
                routes: [
                  GoRoute(path: 'water', builder: (context, state) => const WaterScreen()),
                  GoRoute(
                    path: 'saved-meals',
                    builder: (context, state) => const SavedMealsScreen(),
                  ),
                  GoRoute(
                    path: 'summary',
                    builder: (context, state) => const NutritionSummaryScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.health,
                builder: (context, state) => const HealthScreen(),
                routes: [
                  GoRoute(path: 'weight', builder: (context, state) => const WeightScreen()),
                  GoRoute(
                    path: 'measurements',
                    builder: (context, state) => const MeasurementsScreen(),
                    routes: [
                      GoRoute(
                        path: ':type',
                        builder: (context, state) =>
                            MeasurementHistoryScreen(type: state.pathParameters['type']!),
                      ),
                    ],
                  ),
                  GoRoute(path: 'sleep', builder: (context, state) => const SleepScreen()),
                  GoRoute(
                    path: 'checkin',
                    builder: (context, state) => const CheckinScreen(),
                    routes: [
                      GoRoute(
                        path: 'history',
                        builder: (context, state) => const CheckinHistoryScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.habits,
                builder: (context, state) => const HabitsScreen(),
                routes: [
                  GoRoute(
                    path: 'reminders/history',
                    builder: (context, state) => const NotificationHistoryScreen(),
                  ),
                  GoRoute(path: 'hygiene', builder: (context, state) => const HygieneScreen()),
                  GoRoute(
                    path: 'medication',
                    builder: (context, state) => const MedicationScreen(),
                  ),
                  GoRoute(path: 'recovery', builder: (context, state) => const RecoveryScreen()),
                  GoRoute(
                    path: 'screen-time',
                    builder: (context, state) => const ScreenTimeScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.money,
                builder: (context, state) => const MoneyScreen(),
                routes: [
                  GoRoute(path: 'expenses', builder: (context, state) => const ExpensesScreen()),
                  GoRoute(path: 'budgets', builder: (context, state) => const BudgetsScreen()),
                  GoRoute(
                    path: 'analysis',
                    builder: (context, state) => const MoneyAnalysisScreen(),
                  ),
                  GoRoute(
                    path: 'recurring',
                    builder: (context, state) => const RecurringExpensesScreen(),
                  ),
                  GoRoute(
                    path: 'categories',
                    builder: (context, state) => const CategoriesScreen(),
                  ),
                  GoRoute(
                    path: 'debts',
                    builder: (context, state) => const DebtsScreen(),
                    routes: [
                      GoRoute(path: 'new', builder: (context, state) => const DebtFormScreen()),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            DebtDetailScreen(id: state.pathParameters['id']!),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                DebtFormScreen(id: state.pathParameters['id']),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.insights,
        builder: (context, state) => const InsightsScreen(),
        routes: [
          GoRoute(
            path: 'report/:kind',
            builder: (context, state) => ReportScreen(
              kind: ReportKind.values.byName(state.pathParameters['kind']!),
              selection: switch (state.extra) {
                final Selection s => s,
                _ => (
                  period: ReportPeriod.week,
                  range: periodRange(ReportPeriod.week, ref.read(todayProvider)),
                ),
              },
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.addWeight,
        pageBuilder: (context, state) =>
            _SheetPage<void>(key: state.pageKey, builder: (_) => const AddWeightSheet()),
      ),
      GoRoute(
        path: Routes.addWater,
        pageBuilder: (context, state) =>
            _SheetPage<void>(key: state.pageKey, builder: (_) => const WaterSheet()),
      ),
      GoRoute(
        path: Routes.addSleep,
        pageBuilder: (context, state) =>
            _SheetPage<void>(key: state.pageKey, builder: (_) => const SleepSheet()),
      ),
      GoRoute(
        path: Routes.foods,
        builder: (context, state) =>
            FoodSearchScreen(pick: state.uri.queryParameters['pick'] == '1'),
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (context, state) => ExerciseDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/workout/:id',
        builder: (context, state) => WorkoutDetailScreen(id: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => switch (state.extra) {
              final WorkoutSession s => CardioLogScreen(kind: s.kind, existing: s),
              _ => WorkoutDetailScreen(id: state.pathParameters['id']!),
            },
          ),
        ],
      ),
      GoRoute(
        path: '/log-cardio/:kind',
        builder: (context, state) =>
            CardioLogScreen(kind: WorkoutKind.fromCode(state.pathParameters['kind']!)),
      ),
      GoRoute(
        path: '/gps/:kind',
        builder: (context, state) =>
            GpsWorkoutScreen(kind: WorkoutKind.fromCode(state.pathParameters['kind']!)),
      ),
      GoRoute(path: Routes.newActivity, builder: (context, state) => const ActivityEditorScreen()),
      GoRoute(
        path: '/activity/:id',
        builder: (context, state) => ActivityDetailScreen(id: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => ActivityEditorScreen(id: state.pathParameters['id']),
          ),
          GoRoute(
            path: 'timer',
            builder: (context, state) => TimerScreen(activityId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: Routes.newReminder, builder: (context, state) => const ReminderEditorScreen()),
      GoRoute(
        path: '/reminder/:id',
        builder: (context, state) => ReminderEditorScreen(id: state.pathParameters['id']),
      ),
      GoRoute(path: Routes.addMeal, builder: (context, state) => const MealFormScreen()),
      GoRoute(
        path: '/meal/:id',
        builder: (context, state) => switch (state.extra) {
          final Meal meal => MealFormScreen(existing: meal),
          _ => const MealMissingScreen(),
        },
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'profile',
            builder: (context, state) => const EditSetupScreen(section: SetupSection.profile),
          ),
          GoRoute(
            path: 'goals',
            builder: (context, state) => const EditSetupScreen(section: SetupSection.goals),
          ),
          GoRoute(
            path: 'day',
            builder: (context, state) => const EditSetupScreen(section: SetupSection.day),
          ),
          GoRoute(path: 'home-layout', builder: (context, state) => const CustomiseHomeScreen()),
          GoRoute(path: 'about', builder: (context, state) => const AboutScreen()),
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationSettingsScreen(),
          ),
          GoRoute(path: 'app-lock', builder: (context, state) => const AppLockSettingsScreen()),
          GoRoute(path: 'account', builder: (context, state) => const AccountSyncScreen()),
          GoRoute(path: 'export', builder: (context, state) => const ExportScreen()),
          GoRoute(path: 'delete', builder: (context, state) => const DeleteDataScreen()),
        ],
      ),
      GoRoute(
        path: '/medication/:id',
        builder: (context, state) => MedicationEditorScreen(
          id: state.pathParameters['id'] == 'new' ? null : state.pathParameters['id'],
        ),
      ),
      // Private space: every route sits behind the lock (§7.3).
      GoRoute(
        path: Routes.privateSpace,
        builder: (context, state) => const LockGate(child: PrivateSpaceScreen()),
        routes: [
          GoRoute(
            path: 'habit/:id',
            builder: (context, state) =>
                LockGate(child: PrivateHabitScreen(id: state.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'report',
            builder: (context, state) => const LockGate(child: PrivateReportScreen()),
          ),
          GoRoute(
            path: 'bowel',
            builder: (context, state) => const LockGate(child: BowelScreen()),
          ),
          GoRoute(
            path: 'activities',
            builder: (context, state) => const LockGate(child: PrivateActivitiesScreen()),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    LockGate(child: PrivateActivityScreen(id: state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: 'photos',
            builder: (context, state) => const LockGate(child: ProgressPhotosScreen()),
          ),
          GoRoute(
            path: 'reminders',
            builder: (context, state) => const LockGate(child: PrivateRemindersScreen()),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

enum _Tab {
  insights;

  String label(AppLocalizations l10n) => switch (this) {
    _Tab.insights => l10n.tabInsights,
  };
}

/// A route shown as a bottom sheet over the current screen.
class _SheetPage<T> extends Page<T> {
  const _SheetPage({required this.builder, super.key});
  final WidgetBuilder builder;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    settings: this,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
  );
}
