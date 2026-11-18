import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/features/auth/application/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fake_auth.dart';

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  testWidgets('a fresh install shows only the sign-in screen', (tester) async {
    await app.pump(tester);
    expect(find.text('Praxis'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    await app.dispose(tester);
  });

  testWidgets('signing in leads to onboarding with the Google name filled in', (tester) async {
    await app.pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);
    expect(find.text('2 of 6'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a returning, set-up user goes straight to Home', (tester) async {
    await app.completeOnboarding();
    await app.pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Good morning, Asha'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a remembered session opens Home without signing in, even offline', (tester) async {
    await app.completeOnboarding();
    app
      ..online = false
      ..auth.failWith(const NetworkFailure('offline'));
    await app.pump(tester, session: signedInSession);
    expect(find.text('Good morning, Asha'), findsOneWidget);
    expect(app.auth.signIns, 0);
    await app.dispose(tester);
  });

  testWidgets('offline: explains and does not attempt sign-in', (tester) async {
    app.online = false;
    await app.pump(tester);
    expect(find.textContaining('You are offline'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(app.auth.signIns, 0);
    await app.dispose(tester);
  });

  testWidgets('a build without backend settings says so', (tester) async {
    app.auth.isConfigured = false;
    await app.pump(tester);
    expect(find.textContaining('not set up in this build'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(app.auth.signIns, 0);
    await app.dispose(tester);
  });

  testWidgets('a failed sign-in shows a message and stays on the screen', (tester) async {
    app.auth.failWith(const AuthFailure('google_sign_in_failed'));
    await app.pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not complete'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('cancelling the Google chooser shows no error', (tester) async {
    app.auth.failWith(const AuthFailure('cancelled'));
    await app.pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not complete'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a different account must confirm erasing the existing data', (tester) async {
    await app.completeOnboarding();
    app.auth.next = const Ok(otherAccount);
    await app.pump(tester, session: const SessionState(account: testAccount));

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Use a different account?'), findsOneWidget);
    expect(find.textContaining('asha@example.com'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(await app.db.select(app.db.weightLogs).get(), hasLength(1));

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase and continue'));
    // Erasing touches files and both databases (real I/O).
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);
    expect(await app.db.select(app.db.weightLogs).get(), isEmpty);
    await app.dispose(tester);
  });
}
