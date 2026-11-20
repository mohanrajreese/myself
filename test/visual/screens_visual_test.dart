@Tags(['visual'])
library;

import 'dart:io';

import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:fitbuddy/features/settings/application/theme_mode_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../widget/onboarding_test.dart' show field;

/// Renders each Phase 1 screen to `test/visual/renders/<name>.png` with the
/// real fonts, for comparison with the design canvas.
///
///   flutter test --tags visual --update-goldens test/visual
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(File(file).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$w.ttf',
  ]);
  await load('PlusJakartaSans', [
    for (final w in ['SemiBold', 'Bold']) 'assets/fonts/PlusJakartaSans-$w.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (flutterRoot != null && icons.existsSync()) {
    await load('MaterialIcons', [icons.path]);
  }
}

Future<void> _shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MediaQuery).first, matchesGoldenFile('renders/$name.png'));

Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

const _draft = SetupDraft(
  name: 'Asha Rao',
  weightText: '91.8',
  heightText: '172.5',
  workoutDays: {1, 3, 5},
  wakeTime: '07:00',
);

void main() {
  setUpAll(_loadFonts);

  testWidgets('sign-in', (tester) async {
    final app = AppHarness();
    await app.pump(tester);
    await _shot(tester, '01_sign_in');
    await app.dispose(tester);
  });

  testWidgets('onboarding', (tester) async {
    final app = AppHarness();
    await app.pump(tester, session: signedInSession);
    await tester.enterText(field('Height'), '172.5');
    await tester.enterText(field('Current weight'), '91.8');
    await tester.pumpAndSettle();
    await _shot(tester, '02_profile');
    await _continue(tester);
    await tester.tap(find.text('Lose weight'));
    await tester.pumpAndSettle();
    await _shot(tester, '03_goals');
    await _continue(tester);
    await tester.tap(find.bySemanticsLabel('Monday'));
    await tester.tap(find.bySemanticsLabel('Wednesday'));
    await tester.tap(find.bySemanticsLabel('Friday'));
    await tester.tap(find.text('Water reminders'));
    await tester.pumpAndSettle();
    await _shot(tester, '04_day');
    await _continue(tester);
    await _shot(tester, '05_permissions');
    await _continue(tester);
    await _shot(tester, '06_summary');
    await app.dispose(tester);
  });

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    testWidgets('home and settings (${mode.name})', (tester) async {
      final app = AppHarness();
      await app.completeOnboarding(draft: _draft);
      await app.pump(
        tester,
        session: signedInSession,
        themeMode: mode,
        size: const Size(390, 1080),
      );
      await _shot(tester, '07_home_${mode.name}');
      if (mode == AppThemeMode.light) {
        await tester.tap(find.text('Weight'));
        await tester.pumpAndSettle();
        await _shot(tester, '08_add_weight');
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Profile and settings'));
      await tester.pumpAndSettle();
      await _shot(tester, '09_settings_${mode.name}');
      await app.dispose(tester);
    });
  }
}
