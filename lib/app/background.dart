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
import '../features/reminders/data/drift_reminder_repository.dart';
import 'notification_setup.dart';
import 'reminder_service.dart';

/// WorkManager name of the reminder top-up job (05 §A5).
const reminderTopUpTask = 'reminder-top-up';

/// Opens what a background isolate needs to act on reminders. Returns null
/// when the database key is unavailable (for example before first unlock).
Future<(ReminderService, AppDatabase)?> _openServices() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final key = (await DatabaseKeyManager(const SecureSecretStore()).keyFor(DatabaseId.app))
      .valueOrNull;
  if (key == null) return null;
  final db = AppDatabase(openEncryptedDatabase(name: AppDatabase.databaseName, hexKey: key));
  final gateway = await createNotificationGateway(
    onTap: (_) {},
    onBackgroundTap: notificationTapBackground,
  );
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

Future<void> registerReminderTopUp() async {
  await Workmanager().initialize(reminderTopUpDispatcher);
  await Workmanager().registerPeriodicTask(
    reminderTopUpTask,
    reminderTopUpTask,
    frequency: const Duration(hours: 6),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
