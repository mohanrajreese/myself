import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../core/database/app_database.dart';
import '../core/database/encrypted_connection.dart';
import '../core/database/settings_repository.dart';
import '../core/encryption/database_key_manager.dart';
import '../core/encryption/secure_secret_store.dart';
import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/notification_state_store.dart';
import '../core/platform/alarm_capabilities.dart';
import '../core/platform/device_time_zone.dart';
import '../core/utils/clock.dart';
import '../core/utils/id_generator.dart';
import '../features/activities/data/drift_activity_repository.dart';
import '../features/money/data/drift_money_repository.dart';
import '../features/reminders/data/drift_reminder_repository.dart';
import 'money_reminder_source.dart';
import '../core/database/private_database.dart';
import '../features/medication/data/drift_medication_repository.dart';
import '../features/private_space/data/drift_sensitive_reminder_repository.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import '../core/sync/supabase_sync_remote.dart';
import '../core/sync/sync_engine.dart';
import '../features/auth/application/session.dart';
import '../features/auth/data/supabase_google_auth_repository.dart';
import 'notification_setup.dart';
import 'sync_controller.dart';
import 'push_controller.dart';
import '../core/platform/push_messaging.dart';
import '../core/sync/push_registry.dart';
import 'private_reminder_source.dart';
import 'reminder_service.dart';

/// WorkManager name of the reminder top-up job (05 §A5).
const reminderTopUpTask = 'reminder-top-up';

/// WorkManager name of the hourly sync job (R-07); runs only with a network.
const syncTask = 'sync';

/// Opens what a background isolate needs to act on reminders. Returns null
/// when the database key is unavailable (for example before first unlock).
Future<(ReminderService, AppDatabase)?> _openServices() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final key = (await DatabaseKeyManager(const SecureSecretStore()).keyFor(DatabaseId.app)).valueOrNull;
  if (key == null) return null;
  final db = AppDatabase(openEncryptedDatabase(name: AppDatabase.databaseName, hexKey: key));
  final privateKey = (await DatabaseKeyManager(const SecureSecretStore()).keyFor(DatabaseId.private)).valueOrNull;
  final privateDb = privateKey == null
      ? null
      : PrivateDatabase(openEncryptedDatabase(name: PrivateDatabase.databaseName, hexKey: privateKey));
  final gateway = await createNotificationGateway(onTap: (_) {}, onBackgroundTap: notificationTapBackground);
  final timeZone = DeviceTimeZone();
  const ids = UuidV7Generator();
  final service = ReminderService(
    reminders: DriftReminderRepository(db, clock: systemClock, ids: ids),
    activities: DriftActivityRepository(db, clock: systemClock, ids: ids, timeZone: timeZone),
    settings: SettingsRepository(db, clock: systemClock),
    store: NotificationStateStore(db),
    gateway: gateway,
    capabilities: DeviceAlarmCapabilities(),
    timeZone: timeZone,
    clock: systemClock,
    privateSource: privateDb == null
        ? null
        : DevicePrivateReminderSource(
            medications: DriftMedicationRepository(privateDb, clock: systemClock, ids: ids),
            sensitive: DriftSensitiveReminderRepository(privateDb, clock: systemClock, ids: ids),
            genericTitle: deviceLocalizations().genericReminderTitle,
          ),
    extraSources: [
      MoneyReminderSource(
        money: DriftMoneyRepository(db, clock: systemClock, ids: ids, timeZone: timeZone),
        text: moneyReminderText(deviceLocalizations()),
        clock: systemClock,
      ),
    ],
  );
  return (service, db);
}

/// Notification buttons pressed while the app is closed (§5.15C).
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  final tap = LocalNotificationGateway.tapFrom(response);
  if (tap == null || tap.action == null) return;
  final opened = await _openServices();
  if (opened == null) return;
  final (service, db) = opened;
  try {
    await service.handle(tap);
  } finally {
    await db.close();
  }
}

/// Keeps the seven-day window full and recovers after a reboot, update or
/// clock change (05 §A5).
@pragma('vm:entry-point')
void reminderTopUpDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task == syncTask) return backgroundSync();
    final opened = await _openServices();
    if (opened == null) return false;
    final (service, db) = opened;
    try {
      await service.replan();
      return true;
    } on Object {
      return false;
    } finally {
      await db.close();
    }
  });
}

Future<void> registerBackgroundJobs() async {
  await Workmanager().initialize(reminderTopUpDispatcher);
  await Workmanager().registerPeriodicTask(
    reminderTopUpTask,
    reminderTopUpTask,
    frequency: const Duration(hours: 6),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
  await Workmanager().registerPeriodicTask(
    syncTask,
    syncTask,
    frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Pushes and pulls with the app closed. Opens only the main database: the
/// sync engine never sees private records.
Future<bool> backgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const config = AppConfig.fromEnvironment;
  if (!config.hasBackend) return true;
  const secrets = SecureSecretStore();
  final key = (await DatabaseKeyManager(secrets).keyFor(DatabaseId.app)).valueOrNull;
  if (key == null) return false;
  final db = AppDatabase(openEncryptedDatabase(name: AppDatabase.databaseName, hexKey: key));
  try {
    final settings = SettingsRepository(db, clock: systemClock);
    if (await settings.read(SessionKeys.signedIn) != true) return true;
    final supabase = await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(localStorage: SecureSessionStorage(secrets)),
    );
    final result = await SyncEngine(db: db, remote: SupabaseSyncRemote(supabase.client), clock: systemClock).syncNow();
    if (result.failed == 0 && !result.authPaused) {
      await settings.write(SyncController.lastSyncKey, systemClock.now().toUtc().toIso8601String());
    }
    return result.failed == 0 || result.authPaused;
  } on Object {
    return false;
  } finally {
    await db.close();
  }
}

FirebaseOptions firebaseOptions(AppConfig c) => FirebaseOptions(
  apiKey: c.firebaseApiKey,
  appId: c.firebaseAppId,
  messagingSenderId: c.firebaseSenderId,
  projectId: c.firebaseProjectId,
);

/// A data-only push while the app is closed: shows fixed text for its type,
/// if the user wants that type (§5.15I). Payloads hold no health data.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  final m = pushMessageFrom(message.data);
  if (m == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  var prefs = const PushPreferences();
  final key = (await DatabaseKeyManager(const SecureSecretStore()).keyFor(DatabaseId.app)).valueOrNull;
  if (key != null) {
    final db = AppDatabase(openEncryptedDatabase(name: AppDatabase.databaseName, hexKey: key));
    try {
      prefs = PushPreferences.fromJson(await SettingsRepository(db, clock: systemClock).read(PushPreferences.key));
    } finally {
      await db.close();
    }
  }
  if (!pushAllowed(m.type, prefs)) return;
  final request = pushNotification(m, deviceLocalizations());
  if (request == null) return;
  final gateway = await createNotificationGateway(onTap: (_) {}, onBackgroundTap: notificationTapBackground);
  await gateway.show(request);
}
