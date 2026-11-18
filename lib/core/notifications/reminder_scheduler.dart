import '../scheduling/occurrence_calculator.dart';
import '../scheduling/reminder_planner.dart';
import '../utils/clock.dart';
import '../utils/local_date.dart';
import 'notification_gateway.dart';
import 'notification_state_store.dart';

/// A reminder as the scheduler needs it: the plan plus what to display.
final class SchedulableReminder {
  const SchedulableReminder({
    required this.plan,
    required this.channelId,
    required this.title,
    this.body,
    this.vibrate = true,
    this.secret = false,
    this.soundUri,
  });

  final PlannerReminder plan;
  final String channelId;
  final String title;
  final String? body;
  final bool vibrate;
  final bool secret;
  final String? soundUri;
}

/// Outcome of one run, for logging and tests.
typedef ScheduleSummary = ({int scheduled, int cancelled, int moved, int expired});

/// Brings Android's pending notifications in line with the plan (05 §A5).
/// Idempotent: running it twice changes nothing, so a reboot, timezone
/// change or app update cannot create duplicates.
class ReminderScheduler {
  ReminderScheduler({
    required this.store,
    required this.gateway,
    required this.clock,
    this.planner = const ReminderPlanner(),
  });

  final NotificationStateStore store;
  final NotificationGateway gateway;
  final Clock clock;
  final ReminderPlanner planner;

  static String localKey(LocalOccurrence o) => o.toString().replaceFirst(' ', 'T');

  Future<ScheduleSummary> run(
    List<SchedulableReminder> reminders, {
    required TimeZoneRules zone,
    QuietHours? quietHours,
    Set<(String, LocalDate)> done = const {},
    bool exactAllowed = true,
    int days = 7,
  }) async {
    final now = clock.now().toUtc();
    final byId = {for (final r in reminders) r.plan.id: r};
    final planned = planner.plan(
      [for (final r in reminders) r.plan],
      now: now,
      zone: zone,
      days: days,
      quietHours: quietHours,
      done: done,
    );
    final settled = await store.settledKeys(now.subtract(const Duration(days: 2)));
    final desired = {
      for (final o in planned)
        if (!settled.contains('${o.reminderId}@${localKey(o.local)}'))
          '${o.reminderId}@${localKey(o.local)}': o,
    };

    var scheduled = 0, cancelled = 0, moved = 0, expired = 0;
    final existing = await store.active();
    final kept = <String>{};
    for (final record in existing) {
      if (record.status == NotificationStatus.snoozed) {
        // A snoozed reminder stays unless its reminder is gone or switched off.
        if (!byId.containsKey(record.reminderId)) {
          await gateway.cancel(record.id);
          await store.setStatus(record.id, NotificationStatus.cancelled);
          cancelled++;
        } else {
          kept.add(record.key);
        }
        continue;
      }
      if (!record.at.isAfter(now)) {
        // Already shown with no response.
        await store.setStatus(record.id, NotificationStatus.expired);
        expired++;
        continue;
      }
      final want = desired[record.key];
      if (want == null) {
        await gateway.cancel(record.id);
        await store.setStatus(record.id, NotificationStatus.cancelled);
        cancelled++;
        continue;
      }
      kept.add(record.key);
      final exact = want.exact && exactAllowed;
      if (want.fireAt != record.at || exact != record.exact) {
        await store.reschedule(record.id, at: want.fireAt, exact: exact, deferred: want.deferred);
        await gateway.schedule(_request(record.id, byId[want.reminderId]!, want.fireAt, exact));
        moved++;
      }
    }
    for (final entry in desired.entries) {
      if (kept.contains(entry.key)) continue;
      final o = entry.value;
      final r = byId[o.reminderId]!;
      final exact = o.exact && exactAllowed;
      final record = await store.add(
        reminderId: o.reminderId,
        occurrenceLocal: localKey(o.local),
        at: o.fireAt,
        channelId: r.channelId,
        exact: exact,
        deferred: o.deferred,
      );
      await gateway.schedule(_request(record.id, r, o.fireAt, exact));
      scheduled++;
    }
    return (scheduled: scheduled, cancelled: cancelled, moved: moved, expired: expired);
  }

  NotificationRequest _request(int id, SchedulableReminder r, DateTime at, bool exact) =>
      NotificationRequest(
        id: id,
        at: at,
        channelId: r.channelId,
        title: r.title,
        body: r.body,
        exact: exact,
        secret: r.secret,
        vibrate: r.vibrate,
        soundUri: r.soundUri,
      );
}
