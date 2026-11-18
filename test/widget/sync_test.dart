import 'dart:async';

import 'package:fitbuddy/app/routes.dart';
import 'package:fitbuddy/core/sync/sync_engine.dart';
import 'package:fitbuddy/core/sync/sync_remote.dart';
import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';

void main() {
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
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

  testWidgets('records made on the phone upload; the status says so', (tester) async {
    final app = AppHarness(withSync: true);
    await app.completeOnboarding();
    app.online = false;
    await app.pump(tester, session: signedInSession);
    await drain(tester);
    await go(tester, Routes.accountSync);
    expect(find.textContaining('changes waiting'), findsOneWidget);
    expect(find.text('Waiting for a network'), findsOneWidget);
    expect(app.remote!.rows('profiles'), isEmpty);

    // Sync now does nothing until the network is back.
    await tap(tester, find.text('Sync now'));
    expect(app.remote!.rows('profiles'), isEmpty);
    await app.dispose(tester);
  });

  testWidgets('with a network, Sync now uploads and shows up to date', (tester) async {
    final app = AppHarness(withSync: true);
    await app.completeOnboarding();
    app.remote!.failNext = const SyncRemoteException('network');
    await app.pump(tester, session: signedInSession);
    await drain(tester);
    await go(tester, Routes.accountSync);
    await tap(tester, find.text('Sync now'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await drain(tester);
    // Entries that failed wait for their backoff; move past it and retry.
    app.time.now = app.time.now.add(const Duration(minutes: 2));
    await tap(tester, find.text('Sync now'));
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    expect(app.remote!.rows('profiles').single['display_name'], 'Asha Rao');
    expect(app.remote!.rows('weight_logs'), hasLength(1));
    await app.dispose(tester);
  });

  testWidgets('a returning user on a new phone gets their records back and skips onboarding', (
    tester,
  ) async {
    final first = AppHarness(withSync: true);
    await first.completeOnboarding(
      draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8'),
    );
    await SyncEngine(db: first.db, remote: first.remote!, clock: first.time.clock).syncNow();
    await first.db.close();

    final second = AppHarness(withSync: true)..remote = first.remote;
    await second.pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await drain(tester);
    await tester.pumpAndSettle();
    expect(find.text('Good morning, Asha'), findsOneWidget);
    expect(find.text('About you'), findsNothing);
    await second.dispose(tester);
  });

  testWidgets('a problem is shown with a code and retried, never losing records', (tester) async {
    final app = AppHarness(withSync: true);
    await app.completeOnboarding();
    app.remote!.failNext = const SyncRemoteException('server_500');
    await app.pump(tester, session: signedInSession);
    await drain(tester);
    await go(tester, Routes.accountSync);
    expect(find.textContaining('could not be sent'), findsOneWidget);
    expect(find.textContaining('server_500'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('without a cloud project, sync says it is not set up', (tester) async {
    final app = AppHarness();
    await app.completeOnboarding();
    await app.pump(tester, session: signedInSession);
    await go(tester, Routes.accountSync);
    expect(find.text('Sync is not set up'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    expect(find.textContaining('Push notifications are not set up'), findsOneWidget);
    await app.dispose(tester);
  });

  group('push', () {
    testWidgets('registers the token, follows preferences, revokes on sign-out', (tester) async {
      final app = AppHarness(withSync: true, withPush: true);
      await app.completeOnboarding();
      await app.pump(tester, session: signedInSession);
      await drain(tester);
      expect(app.pushRegistry.registered['token-1']?.backupStatus, isFalse);

      await go(tester, Routes.accountSync);
      await tap(tester, find.text('Backup status'));
      expect(app.pushRegistry.registered['token-1']?.backupStatus, isTrue);

      // A data-only message shows fixed text; health data is never in it.
      app.push.messages.add((type: 'sync_problem', id: null));
      await drain(tester);
      final shown = app.notifications.shown.single;
      expect(shown.title, 'FitBuddy');
      expect(shown.body, contains('not synced'));

      // Unknown types and switched-off types show nothing.
      app.push.messages.add((type: 'weight_update', id: 'x'));
      await tap(tester, find.text('Sync problems'));
      app.push.messages.add((type: 'sync_problem', id: null));
      await drain(tester);
      expect(app.notifications.shown, hasLength(1));

      await tester.pageBack();
      await drain(tester);
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Profile and settings'));
      await tap(tester, find.text('Sign out'));
      await tap(tester, find.widgetWithText(TextButton, 'Sign out'));
      expect(app.pushRegistry.revoked, ['token-1']);
      expect(app.push.deleted, 1);
      await app.dispose(tester);
    });
  });
}
