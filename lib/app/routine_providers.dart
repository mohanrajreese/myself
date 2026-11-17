import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_gateway.dart';
import '../core/notifications/notification_state_store.dart';
import '../core/platform/alarm_capabilities.dart';
import '../core/utils/local_date.dart';
import '../features/activities/data/drift_activity_repository.dart';
import '../features/activities/domain/activity.dart';
import '../features/activities/domain/activity_day.dart';
import '../features/activities/domain/activity_repository.dart';
import '../features/reminders/data/drift_reminder_repository.dart';
import '../features/reminders/domain/reminder.dart';
import '../features/reminders/domain/reminder_repository.dart';
import '../features/timers/data/drift_timer_repository.dart';
import '../features/timers/domain/timer_repository.dart';
import '../features/timers/domain/timer_session.dart';
import 'providers.dart';
import 'reminder_service.dart';

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => DriftActivityRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    timeZone: ref.watch(timeZoneSourceProvider),
  ),
);

final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => DriftReminderRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final timerRepositoryProvider = Provider<TimerRepository>(
  (ref) => DriftTimerRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final notificationStateStoreProvider = Provider<NotificationStateStore>(
  (ref) => NotificationStateStore(ref.watch(appDatabaseProvider)),
);

/// Overridden at start-up with the plugin-backed gateway and in tests with a fake.
final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => throw StateError('not provided'),
);
final alarmCapabilitiesProvider = Provider<AlarmCapabilities>((ref) => DeviceAlarmCapabilities());

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(
    reminders: ref.watch(reminderRepositoryProvider),
    activities: ref.watch(activityRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    store: ref.watch(notificationStateStoreProvider),
    gateway: ref.watch(notificationGatewayProvider),
    capabilities: ref.watch(alarmCapabilitiesProvider),
    timeZone: ref.watch(timeZoneSourceProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Re-plans reminders after a change, without blocking the screen.
void replanReminders(WidgetRef ref) => unawaited(ref.read(reminderServiceProvider).replan());

final activitiesProvider = StreamProvider<List<Activity>>(
  (ref) => ref.watch(activityRepositoryProvider).watchAll(),
);

final activityProvider = Provider.family<Activity?, String>(
  (ref, id) => ref.watch(activitiesProvider).value?.where((a) => a.id == id).firstOrNull,
);

final activityLogsOnProvider = StreamProvider.family<List<ActivityLog>, LocalDate>(
  (ref, date) => ref.watch(activityRepositoryProvider).watchLogsBetween(date, date),
);

final activityLogsBetweenProvider =
    StreamProvider.family<List<ActivityLog>, ({LocalDate from, LocalDate to})>(
      (ref, range) => ref.watch(activityRepositoryProvider).watchLogsBetween(range.from, range.to),
    );

final activityHistoryProvider = StreamProvider.family<List<ActivityLog>, String>(
  (ref, id) => ref.watch(activityRepositoryProvider).watchLogsFor(id, limit: 100),
);

Now currentNow(WidgetRef ref) {
  final t = ref.read(clockProvider).now().toLocal();
  return (date: LocalDate.fromDateTime(t), minute: t.hour * 60 + t.minute);
}

/// Every active activity's state for [date].
final activityDaysProvider = Provider.family<List<ActivityDay>?, LocalDate>((ref, date) {
  final activities = ref.watch(activitiesProvider).value;
  final logs = ref.watch(activityLogsOnProvider(date)).value;
  if (activities == null || logs == null) return null;
  final t = ref.watch(clockProvider).now().toLocal();
  final now = (date: LocalDate.fromDateTime(t), minute: t.hour * 60 + t.minute);
  return [
    for (final a in activities)
      if (!a.archived)
        ActivityDay.of(a, date, [
          for (final l in logs)
            if (l.activityId == a.id) l,
        ], now: now),
  ];
});

final remindersProvider = StreamProvider<List<Reminder>>(
  (ref) => ref.watch(reminderRepositoryProvider).watchAll(),
);

final notificationHistoryProvider = StreamProvider<List<NotificationRecord>>((ref) {
  final now = ref.watch(clockProvider).now();
  return ref
      .watch(notificationStateStoreProvider)
      .watchHistory(since: now.subtract(const Duration(days: 30)), until: now);
});

final activeTimersProvider = StreamProvider<List<TimerSession>>(
  (ref) => ref.watch(timerRepositoryProvider).watchActive(),
);

final quietHoursProvider = FutureProvider<QuietHoursSetting>(
  (ref) => ref.watch(reminderServiceProvider).quietHours(),
);

typedef ReminderStatus = ({
  bool notifications,
  bool exact,
  bool battery,
  List<String> disabledChannels,
});

/// What Android currently allows; re-read when the screen asks.
final reminderStatusProvider = FutureProvider<ReminderStatus>((ref) async {
  final caps = ref.watch(alarmCapabilitiesProvider);
  return (
    notifications: await ref.watch(notificationGatewayProvider).notificationsAllowed(),
    exact: await caps.canScheduleExactAlarms(),
    battery: await caps.isIgnoringBatteryOptimizations(),
    disabledChannels: await caps.disabledChannels(),
  );
});

/// Notification taps while the app runs; overridden at start-up.
final notificationTapsProvider = StreamProvider<NotificationTap>((ref) => const Stream.empty());

/// The tap that launched the app, if any.
final launchTapProvider = Provider<NotificationTap?>((ref) => null);

/// Stand-in when the notification plugin could not start: nothing is shown,
/// and the status screen reports notifications as unavailable.
final class DisabledNotificationGateway implements NotificationGateway {
  const DisabledNotificationGateway();
  @override
  Future<void> schedule(NotificationRequest request) async {}
  @override
  Future<void> show(NotificationRequest request) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<bool> notificationsAllowed() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> canScheduleExact() async => false;
}
