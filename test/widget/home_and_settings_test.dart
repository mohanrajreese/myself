import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:fitbuddy/features/settings/application/theme_mode_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';
import 'onboarding_test.dart' show field;

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  Future<void> start(WidgetTester tester, {SetupDraft? draft}) async {
    await app.completeOnboarding(
      draft:
          draft ?? const SetupDraft(name: 'Asha Rao', weightText: '91.8', workoutDays: {1, 3, 5}),
    );
    await app.pump(tester, session: signedInSession);
  }

  group('Home', () {
    testWidgets('shows the greeting, date and targets from onboarding', (tester) async {
      await start(tester);
      expect(find.text('Good morning, Asha'), findsOneWidget);
      expect(find.text('Monday, 16 November'), findsOneWidget);
      expect(find.text('Goal 8,000 steps'), findsOneWidget);
      expect(find.text('of 3,200 ml'), findsOneWidget);
      expect(find.text('of 2,750 kcal'), findsOneWidget);
      expect(find.text('of 110 g'), findsOneWidget);
      expect(find.text('Target 8 h'), findsOneWidget);
      expect(find.text('Planned today'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('greets by time of day and shows a rest day', (tester) async {
      app.time.now = DateTime(2026, 11, 17, 19);
      await start(tester);
      expect(find.text('Good evening, Asha'), findsOneWidget);
      expect(find.text('Rest day'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('without targets, cards say so instead of showing numbers', (tester) async {
      await start(
        tester,
        draft: const SetupDraft(name: 'Asha', stepsText: '', sleepHoursText: ''),
      );
      expect(find.text('No target set'), findsNWidgets(4));
      expect(find.text('No workout days set'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets("today's timeline lists the weight recorded during onboarding", (tester) async {
      await start(tester);
      await tester.scrollUntilVisible(find.text('Weight · 91.8 kg'), 200);
      expect(find.text('Weight · 91.8 kg'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('quick add saves a weight and the timeline updates', (tester) async {
      await start(tester);
      await tester.scrollUntilVisible(find.text('Weight'), 200);
      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();
      expect(find.text('Add weight'), findsOneWidget);
      expect(find.text('Last: 91.8 kg'), findsOneWidget);

      await tester.enterText(field('Weight'), '91.2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Add weight'), findsNothing);
      expect(find.text('Weight saved'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Weight · 91.2 kg'), 200);
      expect(await app.db.select(app.db.weightLogs).get(), hasLength(2));
      await app.dispose(tester);
    });

    testWidgets('quick add rejects an impossible weight and keeps the sheet open', (tester) async {
      await start(tester);
      await tester.scrollUntilVisible(find.text('Weight'), 200);
      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Weight'), '0.3');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('That value is outside the allowed range.'), findsOneWidget);
      expect(find.text('Add weight'), findsOneWidget);
      expect(await app.db.select(app.db.weightLogs).get(), hasLength(1));
      await app.dispose(tester);
    });

    testWidgets('each tab opens; unbuilt tabs say so and offer no controls', (tester) async {
      await start(tester);
      for (final tab in ['Fitness', 'Nutrition', 'Health', 'Habits', 'Insights']) {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
        await tester.pumpAndSettle();
        expect(
          find.text("$tab isn't available yet. It will appear here in a later update."),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Good morning, Asha'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('Settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Profile and settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the account and what is waiting to upload', (tester) async {
      await start(tester);
      await openSettings(tester);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('asha@example.com'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sync'), 200);
      expect(find.textContaining('changes saved on this phone, waiting to upload'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('editing goals saves and Home reflects the change', (tester) async {
      await start(tester);
      await openSettings(tester);
      await tester.tap(find.text('Goals'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field('Daily steps')).controller.text, '8000');

      await tester.enterText(field('Daily steps'), '10000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Changes saved'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Goal 10,000 steps'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('editing the profile does not ask for or log a weight', (tester) async {
      await start(tester);
      await openSettings(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(field('Current weight'), findsNothing);
      await tester.enterText(field('Name'), 'Asha R');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Asha R'), findsOneWidget);
      expect(await app.db.select(app.db.weightLogs).get(), hasLength(1));
      await app.dispose(tester);
    });

    testWidgets('an invalid edit is refused with a message', (tester) async {
      await start(tester);
      await openSettings(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Name'), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('theme choice applies at once and is remembered', (tester) async {
      await start(tester);
      await openSettings(tester);
      expect(Theme.of(tester.element(find.text('Theme'))).brightness, Brightness.light);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Theme'))).brightness, Brightness.dark);
      final stored = await app.db
          .customSelect("SELECT value_json FROM local_app_settings WHERE key = 'theme_mode'")
          .getSingle();
      expect(stored.read<String>('value_json'), '"dark"');
      expect(themeModeFromSetting('dark'), AppThemeMode.dark);
      await app.dispose(tester);
    });

    testWidgets('hiding a Home section removes it from Home', (tester) async {
      await start(tester);
      expect(find.text('Quick add'), findsOneWidget);
      await openSettings(tester);
      await tester.tap(find.text('Customise Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quick add'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Quick add'), findsNothing);
      expect(find.text('Essential today'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('sign out asks first, then returns to sign-in and keeps the data', (tester) async {
      await start(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Sign out'), 200);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Sign out')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(app.auth.signOuts, 1);
      expect(await app.db.select(app.db.weightLogs).get(), hasLength(1));
      await app.dispose(tester);
    });
  });
}
