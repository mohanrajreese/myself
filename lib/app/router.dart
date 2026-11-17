import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/widgets/fb_scaffolds.dart';
import '../core/widgets/fb_states.dart';
import '../core/widgets/l10n.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/dashboard/presentation/customise_home_screen.dart';
import '../features/onboarding/application/setup_controller.dart';
import '../features/body_measurements/presentation/measurement_screens.dart';
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
import 'app_shell.dart';
import 'providers.dart';
import 'routes.dart';

/// Whether the signed-in account still has to go through onboarding.
final setupStatusProvider = Provider<SetupStatus>((ref) {
  final account = ref.watch(currentAccountProvider);
  if (account == null) return SetupStatus.unknown;
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
                builder: (context, state) => FbNotBuiltYet(title: _Tab.fitness.label(context.l10n)),
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
                builder: (context, state) => FbNotBuiltYet(title: _Tab.habits.label(context.l10n)),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.insights,
                builder: (context, state) =>
                    FbNotBuiltYet(title: _Tab.insights.label(context.l10n)),
              ),
            ],
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
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

enum _Tab {
  fitness,
  habits,
  insights;

  String label(AppLocalizations l10n) => switch (this) {
    _Tab.fitness => l10n.tabFitness,
    _Tab.habits => l10n.tabHabits,
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
