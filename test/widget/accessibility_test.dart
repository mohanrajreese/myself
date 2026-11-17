import 'dart:async';

import 'package:fitbuddy/app/routes.dart';
import 'package:fitbuddy/features/auth/application/session.dart';
import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:fitbuddy/features/settings/application/theme_mode_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

/// Screens reachable so far, each opened by [open] from a fresh start.
typedef _Screen = ({String name, bool setUp, Future<void> Function(WidgetTester) open});

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }
}

/// Opens [path] as the app would after a tap.
Future<void> _go(WidgetTester tester, String path) async {
  unawaited(GoRouter.of(tester.element(find.byType(Scaffold).first)).push(path));
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
}

Future<void> _settings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Profile and settings'));
  await tester.pumpAndSettle();
}

final List<_Screen> _screens = [
  (name: 'sign-in', setUp: false, open: (tester) async {}),
  (name: 'onboarding profile', setUp: false, open: (tester) async {}),
  (name: 'onboarding goals', setUp: false, open: (tester) => _continue(tester, 1)),
  (name: 'onboarding day', setUp: false, open: (tester) => _continue(tester, 2)),
  (name: 'onboarding permissions', setUp: false, open: (tester) => _continue(tester, 3)),
  (name: 'onboarding summary', setUp: false, open: (tester) => _continue(tester, 4)),
  (name: 'home', setUp: true, open: (tester) async {}),
  (name: 'settings', setUp: true, open: _settings),
  (
    name: 'edit goals',
    setUp: true,
    open: (tester) async {
      await _settings(tester);
      await _tapText(tester, 'Goals');
    },
  ),
  (
    name: 'customise home',
    setUp: true,
    open: (tester) async {
      await _settings(tester);
      await _tapText(tester, 'Customise Home');
    },
  ),
  (name: 'health tab', setUp: true, open: (tester) => _tab(tester, Routes.health)),
  (name: 'weight', setUp: true, open: (tester) => _go(tester, Routes.weight)),
  (name: 'measurements', setUp: true, open: (tester) => _go(tester, Routes.measurements)),
  (
    name: 'add measurement',
    setUp: true,
    open: (tester) async {
      await _go(tester, Routes.measurements);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
    },
  ),
  (name: 'sleep', setUp: true, open: (tester) => _go(tester, Routes.sleep)),
  (name: 'add sleep', setUp: true, open: (tester) => _go(tester, Routes.addSleep)),
  (name: 'check-in', setUp: true, open: (tester) => _go(tester, Routes.checkin)),
  (name: 'check-in history', setUp: true, open: (tester) => _go(tester, Routes.checkinHistory)),
  (name: 'nutrition diary', setUp: true, open: (tester) => _tab(tester, Routes.nutrition)),
  (name: 'water', setUp: true, open: (tester) => _go(tester, Routes.water)),
  (name: 'add water', setUp: true, open: (tester) => _go(tester, Routes.addWater)),
  (name: 'add meal', setUp: true, open: (tester) => _go(tester, Routes.addMeal)),
  (name: 'food search', setUp: true, open: (tester) => _go(tester, Routes.foods)),
  (
    name: 'new food',
    setUp: true,
    open: (tester) async {
      await _go(tester, Routes.foods);
      await _tapText(tester, 'Create a food');
    },
  ),
  (name: 'saved meals', setUp: true, open: (tester) => _go(tester, Routes.savedMeals)),
  (name: 'nutrition summary', setUp: true, open: (tester) => _go(tester, Routes.nutritionSummary)),
  (name: 'about', setUp: true, open: (tester) => _go(tester, Routes.about)),
];

void main() {
  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    for (final screen in _screens) {
      testWidgets('${screen.name} (${mode.name}): contrast, tap targets and labels', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final app = AppHarness();
        if (screen.setUp) {
          await app.completeOnboarding(
            draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8', workoutDays: {1, 3, 5}),
          );
        }
        await app.pump(
          tester,
          session: screen.name == 'sign-in' ? const SessionState() : signedInSession,
          themeMode: mode,
        );
        await screen.open(tester);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
        await app.dispose(tester);
      });
    }
  }

  for (final screen in _screens) {
    testWidgets('${screen.name}: no overflow at double text size on a small phone', (tester) async {
      final app = AppHarness();
      if (screen.setUp) await app.completeOnboarding();
      await app.pump(
        tester,
        session: screen.name == 'sign-in' ? const SessionState() : signedInSession,
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });
  }
}
