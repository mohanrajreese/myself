import 'dart:convert';
import 'dart:io';

import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find
            .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last,
      );
    }
    await tester.ensureVisible(f.last);
    await tester.pump();
    await tester.tap(f.last);
    await drain(tester);
    await tester.pumpAndSettle();
  }

  Future<void> steps(String date, int n) => app.db.customStatement(
    "INSERT INTO step_logs VALUES (?, '2026-11-16T09:00:00.000Z', '2026-11-16T09:00:00.000Z', NULL, ?, ?, "
    "'phone_sensor', 'UTC', NULL)",
    ['s$date', date, n],
  );

  Future<void> openInsights(WidgetTester tester) async {
    await app.completeOnboarding(
      draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8'),
    );
    await app.pump(tester, session: signedInSession);
    await drain(tester);
    // Insights lives in the profile menu (owner, 20 Nov 2026).
    await tap(tester, find.byTooltip('Profile and settings'));
    await tap(tester, find.text('Insights'));
    await drain(tester);
  }

  testWidgets('a first week has nothing to compare and says so', (tester) async {
    await openInsights(tester);
    expect(find.text('16 Nov – 22 Nov 2026'), findsOneWidget);
    expect(find.text('compared with 9 Nov – 15 Nov 2026'), findsOneWidget);
    expect(find.text('Not enough records in both periods to compare yet.'), findsOneWidget);
    expect(find.text('Weight, latest'), findsOneWidget);
    expect(find.text('91.8 kg'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('describes a change from the previous week, then opens the report', (tester) async {
    await steps('2026-11-16', 9000);
    await steps('2026-11-10', 7800);
    await openInsights(tester);
    expect(
      find.text('• Your average daily steps increased by 1,200 compared with the previous week.'),
      findsOneWidget,
    );
    expect(find.text('9,000'), findsOneWidget);
    expect(find.text('1,200 more'), findsOneWidget);

    await tap(tester, find.text('Steps, daily average'));
    expect(find.text('This period'), findsOneWidget);
    expect(find.text('7,800'), findsOneWidget);
    expect(find.text('6 days have no records and are left out of averages.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Chart of 1 days with records out of 7')), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('switches to month, steps back a month, and picks a custom range', (tester) async {
    await openInsights(tester);
    await tap(tester, find.text('Month'));
    expect(find.text('1 Nov – 30 Nov 2026'), findsOneWidget);
    await tap(tester, find.byTooltip('Previous period'));
    expect(find.text('1 Oct – 31 Oct 2026'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Custom'));
    await tap(tester, find.text('Last 14 days'));
    await tap(tester, find.text('Show report'));
    expect(find.text('3 Nov – 16 Nov 2026'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('the next-period arrow is off only at the current period', (tester) async {
    await openInsights(tester);
    final next = find.byTooltip('Next period');
    expect(
      tester
          .widget<IconButton>(find.ancestor(of: next, matching: find.byType(IconButton)).first)
          .onPressed,
      isNull,
    );
    await tap(tester, find.byTooltip('Previous period'));
    expect(
      tester
          .widget<IconButton>(find.ancestor(of: next, matching: find.byType(IconButton)).first)
          .onPressed,
      isNotNull,
    );
    await app.dispose(tester);
  });

  testWidgets('private history needs the app lock', (tester) async {
    await openInsights(tester);
    await tap(tester, find.text('Private history'));
    expect(find.text('Set up the app lock first'), findsOneWidget);
    await app.dispose(tester);
  });

  test('insight wording describes, never claims a cause or gives advice', () {
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, Object?>;
    final texts = [
      for (final e in arb.entries)
        if (e.key.startsWith('insight') && e.value is String) e.value! as String,
    ];
    expect(texts, isNotEmpty);
    for (final t in texts) {
      expect(
        t.toLowerCase(),
        isNot(matches(RegExp(r'\b(because|caused|causes|due to|you should|try to|led to)\b'))),
      );
    }
  });
}
