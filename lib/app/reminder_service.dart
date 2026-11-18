import '../core/database/settings_repository.dart';
import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/notifications/notification_state_store.dart';
import '../core/notifications/reminder_scheduler.dart';
import '../core/notifications/tz_zone.dart';
import '../core/platform/alarm_capabilities.dart';
import '../core/platform/time_zone_source.dart';
import '../core/scheduling/occurrence_calculator.dart';
import '../core/scheduling/reminder_planner.dart';
import '../core/utils/clock.dart';
import '../core/utils/local_date.dart';
import '../features/activities/domain/activity.dart';
import '../features/activities/domain/activity_day.dart';
import '../features/activities/domain/activity_repository.dart';
import '../features/reminders/domain/reminder.dart';
import '../features/reminders/domain/reminder_repository.dart';

/// Quiet hours as stored in settings.
final class QuietHoursSetting {
  const QuietHoursSetting({
    this.enabled = false,
    this.start = 22 * 60 + 30,
    this.end = 6 * 60 + 30,
  });
  final bool enabled;
  final int start;
  final int end;

  static const key = 'quiet_hours';

  QuietHours? get active => enabled && start != end ? QuietHours(start: start, end: end) : null;

  Map<String, Object?> toJson() => {'enabled': enabled, 'start': start, 'end': end};
  static QuietHoursSetting fromJson(Object? json) => switch (json) {
    {'enabled': final bool e, 'start': final int s, 'end': final int n} => QuietHoursSetting(
      enabled: e,
      start: s,
      end: n,
    ),
    _ => const QuietHoursSetting(),
  };
}

/// Snooze presets (§5.15D).
const snoozePresetMinutes = [5, 10, 15, 30];

/// Keeps Android's notifications in step with reminders and activity logs,
/// and applies notification button presses.
final class ReminderService {
  ReminderService({
    required this.reminders,
    required this.activities,
    required this.settings,
    required this.store,
    required this.gateway,
    required this.capabilities,
    required this.timeZone,
    required this.clock,
    TimeZoneRules Function(String id)? zoneFor,
    this.privateSource,
  }) : zoneFor = zoneFor ?? IanaZone.new,
       _scheduler = ReminderScheduler(store: store, gateway: gateway, clock: clock),
       _privateScheduler = ReminderScheduler(
         store: store,
         gateway: gateway,
         clock: clock,
         storeName: 'private',
       );

  /// Sensitive reminders (medication, bowel, private). Null before the
  /// private database is open, for example in a background isolate without
  /// its key.
  final PrivateReminderSource? privateSource;
  final ReminderScheduler _privateScheduler;

  final ReminderRepository reminders;
  final ActivityRepository activities;
  final SettingsRepository settings;
  final NotificationStateStore store;
  final NotificationGateway gateway;
  final AlarmCapabilities capabilities;
  final TimeZoneSource timeZone;
  final Clock clock;
  final TimeZoneRules Function(String id) zoneFor;
  final ReminderScheduler _scheduler;

  static const _windowDays = 7;

  Future<QuietHoursSetting> quietHours() async =>
      QuietHoursSetting.fromJson(await settings.read(QuietHoursSetting.key));

  Future<void> saveQuietHours(QuietHoursSetting value) async {
    await settings.write(QuietHoursSetting.key, value.toJson());
    await replan();
  }

  Future<void> _last = Future<void>.value();

  /// Re-plans every enabled reminder. Safe to call any time: runs one at a
  /// time, so concurrent callers cannot hand out the same notification id.
  Future<ScheduleSummary> replan() {
    final run = _last.then((_) => _replan(), onError: (_) => _replan());
    _last = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<ScheduleSummary> _replan() async {
    // Reminders of archived or deleted activities stay quiet.
    final live = {
      for (final a in await activities.watchAll().first)
        if (!a.archived) a.id,
    };
    final list = [
      for (final r in await reminders.enabled())
        if (r.activityId == null || live.contains(r.activityId)) r,
    ];
    final today = LocalDate.fromDateTime(clock.now().toLocal());
    final done = await _doneDays(list, today);
    final zone = zoneFor(await timeZone.currentTimeZoneId());
    final summary = await _scheduler.run(
      [
        for (final r in list)
          SchedulableReminder(
            plan: r.toPlanner(),
            channelId: channelIdFor(r.channel.code, soundUri: r.soundKey),
            title: r.title,
            body: r.description,
            vibrate: r.vibrate,
            soundUri: r.soundKey,
          ),
      ],
      zone: zone,
      quietHours: (await quietHours()).active,
      done: done,
      exactAllowed: await capabilities.canScheduleExactAlarms(),
      days: _windowDays,
    );
    final private = privateSource;
    if (private != null) {
      await _privateScheduler.run(
        await private.reminders(),
        zone: zone,
        quietHours: (await quietHours()).active,
        exactAllowed: await capabilities.canScheduleExactAlarms(),
        days: _windowDays,
      );
    }
    await store.prune(clock.now().subtract(const Duration(days: 30)));
    return summary;
  }

  /// Days on which a linked activity is already done or skipped, so
  /// "if not done" reminders are left out.
  Future<Set<(String, LocalDate)>> _doneDays(List<Reminder> list, LocalDate today) async {
    final ids = {
      for (final r in list)
        if (r.onlyIfIncomplete && r.activityId != null) r.activityId!,
    };
    if (ids.isEmpty) return const {};
    final end = today.addDays(_windowDays);
    final logs = await activities.watchLogsBetween(today.addDays(-1), end).first;
    final out = <(String, LocalDate)>{};
    final now = clock.now().toLocal();
    for (final id in ids) {
      final activity = await activities.byId(id);
      if (activity == null) continue;
      for (var d = today.addDays(-1); !d.isAfter(end); d = d.addDays(1)) {
        final day = ActivityDay.of(
          activity,
          d,
          [
            for (final l in logs)
              if (l.activityId == id) l,
          ],
          now: (date: LocalDate.fromDateTime(now), minute: now.hour * 60 + now.minute),
        );
        if (day.summary == DayState.done || day.summary == DayState.skipped) out.add((id, d));
      }
    }
    return out;
  }

  /// Applies a notification button. Returns the linked activity id when the
  /// body was tapped, so the app can open it.
  Future<String?> handle(NotificationTap tap, {int? snoozeMinutes}) async {
    final record = await store.byId(tap.notificationId);
    if (record == null) return null;
    if (record.store == 'private') return _handlePrivate(record, tap, snoozeMinutes);
    final reminder = await reminders.byId(record.reminderId);
    // Ad-hoc "remind me again" from Home carries the activity id.
    final linkedActivity =
        reminder?.activityId ??
        (record.reminderId.startsWith('activity:') ? record.reminderId.substring(9) : null);
    final now = clock.now();
    switch (tap.action) {
      case null:
        return linkedActivity;
      case ReminderAction.snooze:
        final minutes = snoozeMinutes ?? reminder?.snoozeMinutes ?? 10;
        final until = now.add(Duration(minutes: minutes));
        await store.snooze(record.id, until);
        await gateway.schedule(
          NotificationRequest(
            id: record.id,
            at: until,
            channelId: channelIdFor(
              (reminder?.channel ?? NotificationChannelKey.routines).code,
              soundUri: reminder?.soundKey,
            ),
            soundUri: reminder?.soundKey,
            title: reminder?.title ?? '',
            body: reminder?.description,
            exact: record.exact,
            vibrate: reminder?.vibrate ?? true,
          ),
        );
        return null;
      case ReminderAction.complete || ReminderAction.skip:
        final complete = tap.action == ReminderAction.complete;
        await gateway.cancel(record.id);
        await store.setStatus(
          record.id,
          complete ? NotificationStatus.completed : NotificationStatus.skipped,
          actedAt: now,
        );
        final activityId = linkedActivity;
        if (activityId != null) {
          final slot = record.occurrenceLocal.split('T');
          final date = LocalDate.parse(slot.first);
          final hm = slot.last.split(':');
          final occurred = date == LocalDate.fromDateTime(now.toLocal())
              ? now
              : DateTime(date.year, date.month, date.day, int.parse(hm[0]), int.parse(hm[1]));
          await activities.addLog(
            activityId,
            LogDraft(
              status: complete ? ActivityLogStatus.completed : ActivityLogStatus.skipped,
              occurredAt: occurred,
              source: LogSource.notification,
              scheduledSlot: int.parse(hm[0]) * 60 + int.parse(hm[1]),
            ),
          );
        }
        await replan();
        return null;
    }
  }

  Future<String?> _handlePrivate(
    NotificationRecord record,
    NotificationTap tap,
    int? snoozeMinutes,
  ) async {
    final now = clock.now();
    final source = privateSource;
    switch (tap.action) {
      case null:
        return 'private';
      case ReminderAction.snooze:
        final until = now.add(Duration(minutes: snoozeMinutes ?? 10));
        await store.snooze(record.id, until);
        await gateway.schedule(
          NotificationRequest(
            id: record.id,
            at: until,
            channelId: record.channelIdOr(channelIdFor(NotificationChannelKey.routines.code)),
            title: source?.genericTitle ?? '',
            secret: true,
          ),
        );
        return null;
      case ReminderAction.complete || ReminderAction.skip:
        final complete = tap.action == ReminderAction.complete;
        await gateway.cancel(record.id);
        await store.setStatus(
          record.id,
          complete ? NotificationStatus.completed : NotificationStatus.skipped,
          actedAt: now,
        );
        await source?.acted(record.reminderId, record.occurrenceLocal, completed: complete);
        return null;
    }
  }
}

/// Supplies sensitive reminders without exposing their text to the
/// scheduler beyond a generic title.
abstract interface class PrivateReminderSource {
  String get genericTitle;
  Future<List<SchedulableReminder>> reminders();

  /// A notification button was pressed for [reminderId] at [occurrenceLocal].
  Future<void> acted(String reminderId, String occurrenceLocal, {required bool completed});
}
