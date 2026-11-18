import 'package:fitbuddy/app/app.dart';

import 'dart:io';

import 'package:fitbuddy/app/fitness_providers.dart';
import 'package:fitbuddy/app/private_providers.dart';
import 'package:fitbuddy/app/private_reminder_source.dart';
import 'package:fitbuddy/core/database/private_database.dart';
import 'package:fitbuddy/core/encryption/file_cipher.dart';
import 'package:fitbuddy/core/encryption/secret_store.dart';
import 'package:fitbuddy/core/security/app_lock.dart';
import 'package:fitbuddy/app/providers.dart';
import 'package:fitbuddy/app/routine_providers.dart';
import 'package:fitbuddy/app/tracking_providers.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/features/auth/application/session.dart';
import 'package:fitbuddy/features/auth/application/session_controller.dart';
import 'package:fitbuddy/features/onboarding/application/setup_controller.dart';
import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:fitbuddy/features/settings/application/theme_mode_controller.dart';
import 'package:fitbuddy/features/settings/presentation/settings_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';
import 'fakes.dart';
import 'memory_sync_remote.dart';

import 'package:fitbuddy/app/push_controller.dart';
import 'package:fitbuddy/app/sync_controller.dart';

const signedInSession = SessionState(account: testAccount, signedIn: true);

/// Everything a widget test needs to run the real app against an in-memory
/// database, a fake sign-in and a clock the test controls.
class AppHarness {
  AppHarness({
    DateTime? now,
    FakeAuthRepository? auth,
    bool withSync = false,
    bool withPush = false,
  }) : time = MutableClock(now ?? DateTime(2026, 11, 16, 9)),
       auth = auth ?? FakeAuthRepository() {
    if (withSync) remote = MemorySyncRemote(clock: () => time.now);
    push.isAvailable = withPush;
  }

  /// Set when the harness was made `withSync`; otherwise sync is off.
  MemorySyncRemote? remote;
  final FakePushMessaging push = FakePushMessaging();
  final FakePushRegistry pushRegistry = FakePushRegistry();

  final AppDatabase db = memoryDatabase();
  final MutableClock time;
  final FakeAuthRepository auth;

  /// One generator for the whole test, so ids stay unique across restarts.
  final SequentialIds ids = SequentialIds();
  bool online = true;
  final MemoryPhotoStore photos = MemoryPhotoStore();
  final FakePhotoPicker picker = FakePhotoPicker();
  final FakeNotificationGateway notifications = FakeNotificationGateway();
  final FakeAlarmCapabilities alarms = FakeAlarmCapabilities();
  final FakeSoundLibrary sounds = FakeSoundLibrary();
  final FakeStepCounter stepCounter = FakeStepCounter();
  final FakeLocationTracker location = FakeLocationTracker();
  final PrivateDatabase privateDb = memoryPrivateDatabase();
  final InMemorySecretStore secrets = InMemorySecretStore();
  final FakeSecureWindow secureWindow = FakeSecureWindow();
  final FakeBiometrics biometrics = FakeBiometrics();
  final FakeUsageReader usage = FakeUsageReader();
  final Directory photoDir = Directory.systemTemp.createTempSync('fb_photos');

  List<Override> overrides({
    SessionState session = const SessionState(),
    AppThemeMode themeMode = AppThemeMode.light,
  }) => [
    appDatabaseProvider.overrideWithValue(db),
    authRepositoryProvider.overrideWithValue(auth),
    initialSessionProvider.overrideWithValue(session),
    initialThemeModeProvider.overrideWithValue(themeMode),
    clockProvider.overrideWithValue(time.clock),
    idGeneratorProvider.overrideWithValue(ids),
    timeZoneSourceProvider.overrideWithValue(const FixedTimeZone()),
    onlineProvider.overrideWith((ref) => Stream.value(online)),
    mealPhotoStoreProvider.overrideWithValue(photos),
    photoPickerProvider.overrideWithValue(picker),
    notificationGatewayProvider.overrideWithValue(notifications),
    alarmCapabilitiesProvider.overrideWithValue(alarms),
    soundLibraryProvider.overrideWithValue(sounds),
    stepCounterProvider.overrideWithValue(stepCounter),
    locationTrackerProvider.overrideWithValue(location),
    privateDatabaseProvider.overrideWithValue(privateDb),
    secretStoreProvider.overrideWithValue(secrets),
    pinStoreProvider.overrideWith((ref) => PinStore(secrets, iterations: 1000)),
    secureWindowProvider.overrideWithValue(secureWindow),
    biometricsProvider.overrideWithValue(biometrics),
    usageReaderProvider.overrideWithValue(usage),
    progressPhotoDirProvider.overrideWithValue(photoDir),
    fileCipherProvider.overrideWithValue(FileCipher(List.filled(32, 7))),
    privateReminderSourceProvider.overrideWith(
      (ref) => DevicePrivateReminderSource(
        medications: ref.watch(medicationRepositoryProvider),
        sensitive: ref.watch(sensitiveReminderRepositoryProvider),
        genericTitle: 'FitBuddy reminder',
      ),
    ),
    if (remote != null) syncRemoteProvider.overrideWithValue(remote),
    pushMessagingProvider.overrideWithValue(push),
    pushRegistryProvider.overrideWithValue(pushRegistry),
    signOutActionProvider.overrideWith(
      (ref) => () async {
        await ref.read(pushControllerProvider.notifier).stop();
        await ref.read(sessionControllerProvider.notifier).signOut();
      },
    ),
  ];

  /// Starts the app. Call again to simulate a restart on the same data.
  Future<void> pump(
    WidgetTester tester, {
    SessionState session = const SessionState(),
    AppThemeMode themeMode = AppThemeMode.light,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides(session: session, themeMode: themeMode),
        child: const FitBuddyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Saves a finished onboarding for [testAccount], as the app would.
  Future<void> completeOnboarding({
    SetupDraft draft = const SetupDraft(name: 'Asha Rao', weightText: '91.8'),
  }) async {
    final container = ProviderContainer(overrides: overrides(session: signedInSession));
    await container.read(setupControllerProvider.future);
    final controller = container.read(setupControllerProvider.notifier)
      ..edit((_) => draft)
      ..prepareGoals();
    final result = await controller.finishOnboarding();
    container.dispose();
    if (!result.isOk) throw StateError('onboarding fixture failed: ${result.failureOrNull}');
  }

  /// Unmounts the app and closes the database so no timers outlive the test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump(const Duration(milliseconds: 1));
  }
}
