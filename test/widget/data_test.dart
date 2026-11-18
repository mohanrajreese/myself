import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:fitbuddy/app/routes.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/features/auth/application/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';
import '../support/fake_auth.dart';

void main() {
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> go(WidgetTester tester, String path) async {
    unawaited(GoRouter.of(tester.element(find.byType(Scaffold).first)).push(path));
    await drain(tester);
    await tester.pumpAndSettle();
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

  Future<void> privateRow(AppHarness app) => app.privateDb.customStatement(
    'INSERT INTO local_bowel_logs (id, created_at, updated_at, occurred_at, local_date, tz, count, consistency, straining) '
    "VALUES ('b1', ?1, ?1, ?1, '2026-11-16', 'UTC', 1, 'normal', 0)",
    ['2026-11-16T09:00:00.000Z'],
  );

  Future<void> setPin(WidgetTester tester, String pin) async {
    await go(tester, Routes.appLock);
    await tap(tester, find.byType(Switch).first);
    await tester.enterText(find.byType(EditableText).at(0), pin);
    await tester.enterText(find.byType(EditableText).at(1), pin);
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.pageBack();
    await drain(tester);
    await tester.pumpAndSettle();
  }

  Map<String, Object?> exported(AppHarness app, {String? password}) {
    final zip = app.saver.saved.values.single;
    final a = ZipDecoder().decodeBytes(zip, password: password);
    return jsonDecode(utf8.decode(a.findFile('praxis.json')!.content)) as Map<String, Object?>;
  }

  group('export', () {
    testWidgets('a passphrase is required by default and must be repeated', (tester) async {
      final app = AppHarness();
      await app.completeOnboarding();
      await app.pump(tester, session: signedInSession);
      await go(tester, Routes.export);
      await tester.enterText(
        find.widgetWithText(TextField, 'Passphrase (at least 8 characters)'),
        'short',
      );
      await tap(tester, find.text('Create export'));
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Passphrase (at least 8 characters)'),
        'correct horse',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Repeat passphrase'), 'correct horsy');
      await tap(tester, find.text('Create export'));
      expect(find.text('The two passphrases are different.'), findsOneWidget);
      expect(app.saver.saved, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Repeat passphrase'), 'correct horse');
      await tap(tester, find.text('Create export'));
      expect(find.text('Export saved'), findsOneWidget);
      expect(app.saver.saved.keys.single, 'praxis-export-2026-11-16.zip');
      final data = exported(app, password: 'correct horse');
      expect(((data['tables']! as Map)['weight_logs']! as List), hasLength(1));
      expect(data['includes_private'], isFalse);
      await app.dispose(tester);
    });

    testWidgets('private data needs the PIN and is then included', (tester) async {
      final app = AppHarness();
      await app.completeOnboarding();
      await privateRow(app);
      await app.pump(tester, session: signedInSession);
      await setPin(tester, '2468');
      await go(tester, Routes.export);
      await tap(tester, find.text('Include private data'));
      expect(find.text('Enter your PIN'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1111');
      await tap(tester, find.text('Unlock'));
      expect(find.text('Wrong PIN'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'PIN'), '2468');
      await tap(tester, find.text('Unlock'));
      await tap(tester, find.text('Protect with a passphrase'));
      await tap(tester, find.text('Create export'));
      final data = exported(app);
      expect(data['includes_private'], isTrue);
      expect(((data['tables']! as Map)['private.local_bowel_logs']! as List), hasLength(1));
      await app.dispose(tester);
    });

    testWidgets('cancelling the save picker saves nothing and says so', (tester) async {
      final app = AppHarness()..saver.cancel = true;
      await app.completeOnboarding();
      await app.pump(tester, session: signedInSession);
      await go(tester, Routes.export);
      await tap(tester, find.text('Protect with a passphrase'));
      await tap(tester, find.text('Create export'));
      expect(find.text('Not saved.'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('deletion', () {
    testWidgets('deleting phone data erases both databases and the lock, then signs out', (
      tester,
    ) async {
      final app = AppHarness();
      await app.completeOnboarding();
      await privateRow(app);
      await app.pump(tester, session: signedInSession);
      await setPin(tester, '2468');
      await go(tester, Routes.deleteData);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Delete phone data'));
      await tap(tester, find.widgetWithText(TextButton, 'Delete phone data'));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(await app.db.select(app.db.weightLogs).get(), isEmpty);
      expect(await app.privateDb.select(app.privateDb.localBowelLogs).get(), isEmpty);
      expect(await app.secrets.read('app_lock_pin'), isNull);
      expect(app.secureWindow.secure, isFalse);
      await app.dispose(tester);
    });

    testWidgets('deleting the account needs the word DELETE and the same Google account', (
      tester,
    ) async {
      final app = AppHarness(withSync: true);
      await app.completeOnboarding();
      await app.pump(tester, session: signedInSession);
      await drain(tester);
      expect(app.remote!.rows('profiles'), isNotEmpty);
      await go(tester, Routes.deleteData);
      await tap(tester, find.text('Keep records here, signed out'));
      await tap(tester, find.text('Delete account…'));
      await tester.enterText(find.byType(TextField).last, 'delete');
      await tester.pump();
      final confirm = find.widgetWithText(TextButton, 'Delete account');
      expect(tester.widget<TextButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'DELETE');
      await tester.pump();

      app.auth.next = const Ok(otherAccount);
      await tap(tester, confirm);
      expect(find.text('Sign in with the same Google account to confirm.'), findsOneWidget);
      expect(app.remote!.rows('profiles'), isNotEmpty);

      app.auth.next = const Ok(testAccount);
      // Let the message close; it covers the button.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Delete account…'));
      await tester.enterText(find.byType(TextField).last, 'DELETE');
      await tester.pump();
      await tap(tester, find.widgetWithText(TextButton, 'Delete account'));
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(app.remote!.rows('profiles'), isEmpty);
      // Kept on the phone, with nothing left to upload.
      expect(await app.db.select(app.db.weightLogs).get(), hasLength(1));
      expect(await app.db.select(app.db.syncOutbox).get(), isEmpty);
      await app.dispose(tester);
    });

    testWidgets('signing in as another account erases private data too (C11)', (tester) async {
      final app = AppHarness();
      await app.completeOnboarding();
      await privateRow(app);
      app.auth.next = const Ok(otherAccount);
      await app.pump(tester, session: const SessionState(account: testAccount));
      await tap(tester, find.text('Continue with Google'));
      await tap(tester, find.text('Erase and continue'));
      expect(await app.privateDb.select(app.privateDb.localBowelLogs).get(), isEmpty);
      await app.dispose(tester);
    });
  });
}
