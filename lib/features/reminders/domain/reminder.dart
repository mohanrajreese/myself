import '../../../core/scheduling/reminder_planner.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/utils/local_date.dart';

enum ReminderKind {
  custom('custom'),
  activity('activity'),
  water('water'),
  workout('workout'),
  sleep('sleep'),
  posture('posture');

  const ReminderKind(this.code);
  final String code;
  static ReminderKind fromCode(String code) => values.firstWhere((k) => k.code == code);
}

/// Android notification channels (§5.15H). Ids are versioned so a changed
/// sound can get a new channel (R-08).
enum NotificationChannelKey {
  alarms('alarms'),
  routines('routines'),
  hydration('hydration'),
  fitness('fitness'),
  medication('medication'),
  sleep('sleep'),
  system('system');

  const NotificationChannelKey(this.code);
  final String code;
  static NotificationChannelKey fromCode(String code) => values.firstWhere((c) => c.code == code);
}

/// An ordinary reminder (§5.15A–B).
final class Reminder {
  const Reminder({
    required this.id,
    required this.kind,
    required this.title,
    required this.rule,
    this.description,
    this.activityId,
    this.onlyIfIncomplete = false,
    this.soundKey,
    this.vibrate = true,
    this.snoozeMinutes = 10,
    this.alarm = false,
    this.quietBehaviour = QuietBehaviour.defer,
    this.enabled = true,
    this.startDate,
    this.endDate,
  });

  final String id;
  final ReminderKind kind;
  final String title;
  final String? description;
  final String? activityId;
  final ScheduleRule rule;
  final bool onlyIfIncomplete;
  final String? soundKey;
  final bool vibrate;
  final int snoozeMinutes;

  /// Important alarm: exact timing and the Important alarms channel.
  final bool alarm;
  final QuietBehaviour quietBehaviour;
  final bool enabled;
  final LocalDate? startDate;
  final LocalDate? endDate;

  NotificationChannelKey get channel {
    if (alarm) return NotificationChannelKey.alarms;
    return switch (kind) {
      ReminderKind.water => NotificationChannelKey.hydration,
      ReminderKind.workout => NotificationChannelKey.fitness,
      ReminderKind.sleep => NotificationChannelKey.sleep,
      _ => NotificationChannelKey.routines,
    };
  }

  List<String> get problems => [
    if (title.trim().isEmpty) 'title_required',
    if (title.trim().length > 80) 'title_too_long',
    ...rule.problems,
    if (snoozeMinutes < 1 || snoozeMinutes > 720) 'snooze_out_of_range',
    if ((kind == ReminderKind.activity || onlyIfIncomplete) && activityId == null)
      'activity_required',
    if (startDate != null && endDate != null && endDate!.isBefore(startDate!)) 'end_before_start',
  ];

  PlannerReminder toPlanner() => PlannerReminder(
    id: id,
    rule: rule,
    quietBehaviour: quietBehaviour,
    alarm: alarm,
    activityId: activityId,
    onlyIfIncomplete: onlyIfIncomplete,
    startDate: startDate,
    endDate: endDate,
  );

  Reminder copyWith({
    String? id,
    ReminderKind? kind,
    String? title,
    String? Function()? description,
    String? Function()? activityId,
    ScheduleRule? rule,
    bool? onlyIfIncomplete,
    String? Function()? soundKey,
    bool? vibrate,
    int? snoozeMinutes,
    bool? alarm,
    QuietBehaviour? quietBehaviour,
    bool? enabled,
    LocalDate? Function()? startDate,
    LocalDate? Function()? endDate,
  }) => Reminder(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    description: description == null ? this.description : description(),
    activityId: activityId == null ? this.activityId : activityId(),
    rule: rule ?? this.rule,
    onlyIfIncomplete: onlyIfIncomplete ?? this.onlyIfIncomplete,
    soundKey: soundKey == null ? this.soundKey : soundKey(),
    vibrate: vibrate ?? this.vibrate,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    alarm: alarm ?? this.alarm,
    quietBehaviour: quietBehaviour ?? this.quietBehaviour,
    enabled: enabled ?? this.enabled,
    startDate: startDate == null ? this.startDate : startDate(),
    endDate: endDate == null ? this.endDate : endDate(),
  );
}

/// Starting points for the preset reminder types (§5.15A).
Reminder reminderPreset(ReminderKind kind, {required String title, required LocalDate today}) =>
    switch (kind) {
      ReminderKind.water => Reminder(
        id: '',
        kind: kind,
        title: title,
        rule: Interval(everyMinutes: 90, start: 8 * 60, end: 20 * 60),
      ),
      ReminderKind.workout => Reminder(
        id: '',
        kind: kind,
        title: title,
        rule: Weekdays(weekdays: {1, 3, 5}, times: [18 * 60 + 30]),
      ),
      ReminderKind.sleep => Reminder(
        id: '',
        kind: kind,
        title: title,
        rule: Daily(times: [22 * 60 + 15]),
      ),
      ReminderKind.posture => Reminder(
        id: '',
        kind: kind,
        title: title,
        rule: Interval(everyMinutes: 120, start: 9 * 60, end: 17 * 60, weekdays: {1, 2, 3, 4, 5}),
      ),
      _ => Reminder(
        id: '',
        kind: kind,
        title: title,
        rule: OneTime(date: today, time: 9 * 60),
      ),
    };
