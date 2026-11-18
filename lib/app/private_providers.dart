import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/private_database.dart';
import '../core/encryption/file_cipher.dart';
import '../core/encryption/secret_store.dart';
import '../core/encryption/secure_secret_store.dart';
import '../core/platform/privacy_platform.dart';
import '../core/security/app_lock.dart';
import '../core/utils/local_date.dart';
import '../features/medication/data/drift_medication_repository.dart';
import '../features/medication/domain/medication.dart';
import '../features/private_space/data/drift_private_repository.dart';
import '../features/private_space/data/drift_sensitive_reminder_repository.dart';
import '../features/private_space/domain/private_records.dart';
import '../features/recovery/data/drift_recovery_repository.dart';
import '../features/recovery/domain/recovery.dart';
import '../features/screen_time/data/drift_screen_time_repository.dart';
import '../features/screen_time/domain/screen_time.dart';
import 'providers.dart';
import 'routine_providers.dart';
import 'screen_time_service.dart';

/// Opened at start-up with its own key; overridden there and in tests.
final privateDatabaseProvider = Provider<PrivateDatabase>(
  (ref) => throw StateError('not provided'),
);
final secretStoreProvider = Provider<SecretStore>((ref) => const SecureSecretStore());
final progressPhotoDirProvider = Provider<Directory?>((ref) => null);
final fileCipherProvider = Provider<FileCipher?>((ref) => null);

final secureWindowProvider = Provider<SecureWindow>((ref) => DeviceSecureWindow());
final biometricsProvider = Provider<Biometrics>((ref) => DeviceBiometrics());
final usageReaderProvider = Provider<UsageReader>((ref) => DeviceUsageReader());

final pinStoreProvider = Provider<PinStore>((ref) => PinStore(ref.watch(secretStoreProvider)));

final privateRepositoryProvider = Provider<PrivateRepository>(
  (ref) => DriftPrivateRepository(
    ref.watch(privateDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    timeZone: ref.watch(timeZoneSourceProvider),
    photoDir: ref.watch(progressPhotoDirProvider),
    cipher: ref.watch(fileCipherProvider),
  ),
);

final sensitiveReminderRepositoryProvider = Provider<SensitiveReminderRepository>(
  (ref) => DriftSensitiveReminderRepository(
    ref.watch(privateDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final medicationRepositoryProvider = Provider<MedicationRepository>(
  (ref) => DriftMedicationRepository(
    ref.watch(privateDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final recoveryRepositoryProvider = Provider<RecoveryRepository>(
  (ref) => DriftRecoveryRepository(ref.watch(appDatabaseProvider), clock: ref.watch(clockProvider)),
);

final screenTimeRepositoryProvider = Provider<ScreenTimeRepository>(
  (ref) => DriftScreenTimeRepository(
    ref.watch(privateDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Overridden at start-up so the alert text is localised.
final screenTimeAlertTitleProvider = Provider<String>((ref) => 'FitBuddy');

final screenTimeServiceProvider = Provider<ScreenTimeService>(
  (ref) => ScreenTimeService(
    reader: ref.watch(usageReaderProvider),
    repo: ref.watch(screenTimeRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    gateway: ref.watch(notificationGatewayProvider),
    clock: ref.watch(clockProvider),
    alertTitle: ref.watch(screenTimeAlertTitleProvider),
  ),
);

final screenTimeSettingsProvider = FutureProvider<ScreenTimeSettings>(
  (ref) => ref.watch(screenTimeServiceProvider).read(),
);
final usageAccessProvider = FutureProvider<bool>(
  (ref) => ref.watch(usageReaderProvider).hasAccess(),
);

final screenTimeDaysProvider =
    StreamProvider.family<List<ScreenTimeDay>, ({LocalDate from, LocalDate to})>(
      (ref, r) => ref.watch(screenTimeRepositoryProvider).watchDays(from: r.from, to: r.to),
    );
final screenTimeAppsProvider =
    StreamProvider.family<List<AppMinutes>, ({LocalDate from, LocalDate to})>(
      (ref, r) => ref.watch(screenTimeRepositoryProvider).watchApps(from: r.from, to: r.to),
    );

final habitTypesProvider = StreamProvider<List<PrivateHabitType>>(
  (ref) => ref.watch(privateRepositoryProvider).watchHabitTypes(),
);
final habitLogsProvider =
    StreamProvider.family<List<PrivateHabitLog>, ({String type, LocalDate from, LocalDate to})>(
      (ref, r) =>
          ref.watch(privateRepositoryProvider).watchHabitLogs(r.type, from: r.from, to: r.to),
    );
final bowelLogsProvider = StreamProvider.family<List<BowelLog>, ({LocalDate from, LocalDate to})>(
  (ref, r) => ref.watch(privateRepositoryProvider).watchBowel(from: r.from, to: r.to),
);
final privateActivitiesProvider = StreamProvider<List<PrivateActivity>>(
  (ref) => ref.watch(privateRepositoryProvider).watchActivities(),
);
final privateActivityLogsProvider = StreamProvider.family<List<PrivateActivityLog>, String>(
  (ref, id) => ref.watch(privateRepositoryProvider).watchActivityLogs(id),
);
final progressPhotosProvider = StreamProvider<List<ProgressPhoto>>(
  (ref) => ref.watch(privateRepositoryProvider).watchPhotos(),
);
final sensitiveRemindersProvider = StreamProvider<List<SensitiveReminder>>(
  (ref) => ref.watch(sensitiveReminderRepositoryProvider).watchAll(),
);

final medicationsProvider = StreamProvider<List<Medication>>(
  (ref) => ref.watch(medicationRepositoryProvider).watchAll(),
);
final doseLogsProvider = StreamProvider.family<List<DoseLog>, ({LocalDate from, LocalDate to})>(
  (ref, r) => ref.watch(medicationRepositoryProvider).watchLogs(from: r.from, to: r.to),
);

final recoveryDayProvider = StreamProvider.family<RecoveryLog?, LocalDate>(
  (ref, d) => ref.watch(recoveryRepositoryProvider).watchDay(d),
);
final recoveryRecentProvider = StreamProvider<List<RecoveryLog>>(
  (ref) => ref.watch(recoveryRepositoryProvider).watchRecent(),
);

/// What the lock screen and gate need.
final class LockView {
  const LockView({
    required this.settings,
    required this.unlocked,
    required this.hasPin,
    this.blockedFor,
  });
  final AppLockSettings settings;
  final bool unlocked;
  final bool hasPin;
  final Duration? blockedFor;
}

/// App lock (P-01, §7.3).
class LockController extends AsyncNotifier<LockView> {
  late LockState _state;

  @override
  Future<LockView> build() async {
    final pins = ref.watch(pinStoreProvider);
    final settings = await pins.readSettings();
    _state = LockState(settings);
    await ref.read(secureWindowProvider).set(secure: settings.enabled);
    return _view(hasPin: await pins.hasPin());
  }

  LockView _view({required bool hasPin}) => LockView(
    settings: _state.settings,
    unlocked: _state.isUnlocked,
    hasPin: hasPin,
    blockedFor: _state.blockedFor(ref.read(clockProvider).now()),
  );

  DateTime get _now => ref.read(clockProvider).now();

  /// Returns false for a wrong PIN or while blocked.
  Future<bool> unlockWithPin(String pin) async {
    if (_state.blockedFor(_now) != null) return false;
    final ok = await ref.read(pinStoreProvider).verify(pin);
    if (ok) {
      _state.unlocked(_now);
    } else {
      _state.wrongPin(_now);
    }
    state = AsyncData(_view(hasPin: true));
    return ok;
  }

  Future<bool> unlockWithBiometrics(String reason) async {
    if (!_state.settings.biometric) return false;
    final ok = await ref.read(biometricsProvider).authenticate(reason);
    if (ok) {
      _state.unlocked(_now);
      state = AsyncData(_view(hasPin: true));
    }
    return ok;
  }

  void lockNow() {
    _state.lockNow();
    state = AsyncData(_view(hasPin: state.value?.hasPin ?? true));
  }

  void movedToBackground() => _state.movedToBackground(_now);

  void returnedToForeground() {
    _state.returnedToForeground(_now);
    state = AsyncData(_view(hasPin: state.value?.hasPin ?? false));
  }

  /// Turns the lock on with a new PIN, or changes the PIN.
  Future<void> setPin(String pin) async {
    final pins = ref.read(pinStoreProvider);
    await pins.setPin(pin);
    await _saveSettings(_state.settings.copyWith(enabled: true));
    _state.unlocked(_now);
    state = AsyncData(_view(hasPin: true));
  }

  Future<void> turnOff() async {
    await ref.read(pinStoreProvider).clear();
    _state = LockState(const AppLockSettings());
    await ref.read(secureWindowProvider).set(secure: false);
    state = AsyncData(_view(hasPin: false));
  }

  Future<void> changeSettings(AppLockSettings settings) async {
    await _saveSettings(settings);
    state = AsyncData(_view(hasPin: state.value?.hasPin ?? false));
  }

  Future<void> _saveSettings(AppLockSettings s) async {
    await ref.read(pinStoreProvider).writeSettings(s);
    _state.settings = s;
    await ref.read(secureWindowProvider).set(secure: s.enabled);
  }
}

final lockControllerProvider = AsyncNotifierProvider<LockController, LockView>(LockController.new);

/// Refreshes screen time without blocking the screen.
void refreshScreenTime(WidgetRef ref) => unawaited(
  ref
      .read(screenTimeServiceProvider)
      .refresh()
      .then((_) => ref.invalidate(usageAccessProvider), onError: (_) {}),
);
