import 'package:fitbuddy/app/providers.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/core/units/units.dart';
import 'package:fitbuddy/features/auth/domain/account.dart';
import 'package:fitbuddy/features/profile/domain/profile.dart';
import 'package:fitbuddy/features/auth/application/session.dart';
import 'package:fitbuddy/features/auth/application/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth.dart';
import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeAuthRepository auth;
  late ProviderContainer container;

  ProviderContainer build([SessionState initial = const SessionState()]) => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      authRepositoryProvider.overrideWithValue(auth),
      initialSessionProvider.overrideWithValue(initial),
      timeZoneSourceProvider.overrideWithValue(const FixedTimeZone()),
    ],
  );

  setUp(() {
    db = memoryDatabase();
    auth = FakeAuthRepository();
    container = build();
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  SessionController controller() => container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);

  test('starts signed out on a fresh install', () {
    expect(state().active, isFalse);
    expect(state().account, isNull);
  });

  group('without sign-in (D2 revised)', () {
    test('a fresh install opens with a local account, no sign-in', () async {
      final settings = container.read(settingsRepositoryProvider);
      final session = await ensureLocalSession(settings);
      expect(session.active, isTrue);
      expect(session.account!.id, isNotEmpty);

      final reloaded = await loadSession(settings);
      expect(reloaded.active, isTrue);
      expect(reloaded.account, session.account);
      expect((await ensureLocalSession(settings)).account, session.account);
    });

    test('an account left signed out is reopened with its data', () async {
      final settings = container.read(settingsRepositoryProvider);
      await controller().signIn();
      await controller().signOut();
      final session = await ensureLocalSession(settings);
      expect(session.active, isTrue);
      expect(session.account, testAccount);
    });

    test('erasing the phone starts a new local account instead of a sign-in', () async {
      await controller().signIn();
      await controller().forget();
      expect(state().active, isTrue);
      expect(state().account!.id, isNot(testAccount.id));
      final reloaded = await loadSession(container.read(settingsRepositoryProvider));
      expect(reloaded.account, state().account);
    });
  });

  group('anonymous cloud user (D2 revised)', () {
    const cloud = Account(id: 'cloud-1');

    Future<Account> startLocal() async {
      final session = await ensureLocalSession(container.read(settingsRepositoryProvider));
      container.dispose();
      container = build(session);
      return session.account!;
    }

    test('first connection creates an anonymous user and moves the profile to it', () async {
      final local = await startLocal();
      await container
          .read(profileRepositoryProvider)
          .save(local.id, const ProfileDraft(displayName: 'Asha'));
      auth
        ..cloudAccount = null
        ..nextAnonymous = const Ok(cloud);

      expect(await controller().connectCloud(), isTrue);

      expect(auth.anonymousSignIns, 1);
      expect(state().account, cloud);
      expect(state().active, isTrue);
      final profiles = container.read(profileRepositoryProvider);
      expect((await profiles.current(cloud.id))!.displayName, 'Asha');
      expect(await profiles.current(local.id), isNull);
      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.where((e) => e.entityTable == 'profiles').map((e) => e.entityId), [cloud.id]);
      expect((await loadSession(container.read(settingsRepositoryProvider))).account, cloud);
    });

    test('a kept cloud session is reused without creating another user', () async {
      await startLocal();
      auth.cloudAccount = cloud;
      expect(await controller().connectCloud(), isTrue);
      expect(await controller().connectCloud(), isTrue);
      expect(auth.anonymousSignIns, 0);
      expect(state().account, cloud);
    });

    test('offline: stays on the device account and tries again later', () async {
      final local = await startLocal();
      auth
        ..cloudAccount = null
        ..nextAnonymous = const Err(NetworkFailure('offline'));
      expect(await controller().connectCloud(), isFalse);
      expect(state().account, local);
      expect(state().active, isTrue);
    });

    test('a build without a cloud project never connects', () async {
      final local = await startLocal();
      auth.isConfigured = false;
      expect(await controller().connectCloud(), isFalse);
      expect(auth.anonymousSignIns, 0);
      expect(state().account, local);
    });
  });

  test('a successful sign-in binds the account and is remembered', () async {
    expect(await controller().signIn(), isA<SignedIn>());
    expect(state().active, isTrue);
    expect(state().account, testAccount);

    final reloaded = await loadSession(container.read(settingsRepositoryProvider));
    expect(reloaded.active, isTrue);
    expect(reloaded.account, testAccount);
  });

  test('a failed sign-in changes nothing', () async {
    auth.failWith(const NetworkFailure('offline'));
    final outcome = await controller().signIn();
    expect((outcome as SignInFailed).failure, const NetworkFailure('offline'));
    expect(state().active, isFalse);
    expect((await loadSession(container.read(settingsRepositoryProvider))).account, isNull);
  });

  test('a remembered session is active without any network call', () {
    container.dispose();
    container = build(const SessionState(account: testAccount, signedIn: true));
    expect(state().active, isTrue);
    expect(auth.signIns, 0);
  });

  test('sign-out keeps the bound account and its data, and returns to signed out', () async {
    await controller().signIn();
    await container.read(weightRepositoryProvider).add(weightG: 91800, entryUnit: MassUnit.kg);
    await controller().signOut();

    expect(state().active, isFalse);
    expect(state().account, testAccount);
    expect(auth.signOuts, 1);
    expect(await db.select(db.weightLogs).get(), hasLength(1));
    final reloaded = await loadSession(container.read(settingsRepositoryProvider));
    expect(reloaded.active, isFalse);
    expect(reloaded.account, testAccount);
  });

  test('signing in again with the same account resumes', () async {
    await controller().signIn();
    await controller().signOut();
    expect(await controller().signIn(), isA<SignedIn>());
    expect(state().active, isTrue);
  });

  test('a different account is not bound until the user agrees to erase', () async {
    await controller().signIn();
    await container.read(weightRepositoryProvider).add(weightG: 91800, entryUnit: MassUnit.kg);
    await controller().signOut();

    auth.next = const Ok(otherAccount);
    final outcome = await controller().signIn() as DifferentAccount;
    expect(outcome.existing, testAccount);
    expect(outcome.incoming, otherAccount);
    expect(state().active, isFalse);
    expect(state().account, testAccount);
    expect(await db.select(db.weightLogs).get(), hasLength(1));

    await controller().replaceAccount(outcome.incoming);
    expect(state().active, isTrue);
    expect(state().account, otherAccount);
    expect(await db.select(db.weightLogs).get(), isEmpty);
    expect(await outboxEntries(db), isEmpty);
  });

  test('declining the erase ends the new session and keeps everything', () async {
    await controller().signIn();
    await controller().signOut();
    auth.next = const Ok(otherAccount);
    await controller().signIn();
    await controller().cancelReplace();
    expect(state().account, testAccount);
    expect(state().active, isFalse);
    expect(auth.signOuts, 2);
  });
}
