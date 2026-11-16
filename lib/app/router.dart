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
import '../features/dashboard/presentation/home_screen.dart';
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
          for (final (path, title) in const [
            (Routes.fitness, _Tab.fitness),
            (Routes.nutrition, _Tab.nutrition),
            (Routes.health, _Tab.health),
            (Routes.habits, _Tab.habits),
            (Routes.insights, _Tab.insights),
          ])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) => FbNotBuiltYet(title: title.label(context.l10n)),
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
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

enum _Tab {
  fitness,
  nutrition,
  health,
  habits,
  insights;

  String label(AppLocalizations l10n) => switch (this) {
    _Tab.fitness => l10n.tabFitness,
    _Tab.nutrition => l10n.tabNutrition,
    _Tab.health => l10n.tabHealth,
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
