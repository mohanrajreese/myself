import 'dart:convert';

import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/utils/local_date.dart';

enum TrackingType {
  boolean('boolean'),
  count('count'),
  numeric('numeric'),
  duration('duration'),
  stopwatch('stopwatch'),
  eventLog('event_log'),
  checklist('checklist');

  const TrackingType(this.code);
  final String code;

  static TrackingType fromCode(String code) => values.firstWhere((t) => t.code == code);

  /// Whether a log carries an amount that adds up towards a target.
  bool get hasAmount => this == count || this == numeric || this == duration || this == stopwatch;
}

/// Whether past logs stay meaningful after changing the tracking type
/// (§5.14). With no logs, anything goes.
bool canChangeTrackingType(TrackingType from, TrackingType to, {required bool hasLogs}) {
  if (from == to || !hasLogs) return true;
  const allowed = {
    (TrackingType.count, TrackingType.numeric),
    (TrackingType.duration, TrackingType.stopwatch),
    (TrackingType.stopwatch, TrackingType.duration),
    (TrackingType.boolean, TrackingType.eventLog),
    (TrackingType.eventLog, TrackingType.boolean),
  };
  return allowed.contains((from, to));
}

enum ActivityPriority {
  essential('essential'),
  optional('optional');

  const ActivityPriority(this.code);
  final String code;
  static ActivityPriority fromCode(String code) => values.firstWhere((p) => p.code == code);
}

final class ChecklistItem {
  const ChecklistItem(this.id, this.label);
  final String id;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};
  static ChecklistItem fromJson(Map<String, Object?> json) =>
      ChecklistItem(json['id']! as String, json['label']! as String);

  static String listToJson(List<ChecklistItem> items) => jsonEncode([for (final i in items) i.toJson()]);
  static List<ChecklistItem> listFromJson(String json) => [
    for (final e in jsonDecode(json) as List<Object?>) fromJson((e! as Map).cast<String, Object?>()),
  ];

  @override
  bool operator ==(Object other) => other is ChecklistItem && other.id == id && other.label == label;
  @override
  int get hashCode => Object.hash(id, label);
}

/// A schedule rule and the first day it applied.
final class ScheduleChange {
  const ScheduleChange({required this.from, required this.rule});
  final LocalDate from;
  final ScheduleRule rule;

  static String listToJson(List<ScheduleChange> changes) => jsonEncode([
    for (final c in changes) {'from': c.from.toString(), 'rule': c.rule.toJson()},
  ]);

  static List<ScheduleChange> listFromJson(String json) => [
    for (final e in jsonDecode(json) as List<Object?>)
      if (e case {'from': final String from, 'rule': final Map<String, Object?> rule})
        ScheduleChange(from: LocalDate.parse(from), rule: ScheduleRule.fromJson(rule)),
  ];

  @override
  bool operator ==(Object other) => other is ScheduleChange && other.from == from && other.rule == rule;
  @override
  int get hashCode => Object.hash(from, rule);
}

/// An ordinary activity definition (§5.14).
final class Activity {
  const Activity({
    required this.id,
    required this.name,
    required this.category,
    required this.iconKey,
    required this.trackingType,
    required this.priority,
    required this.schedule,
    required this.scheduleHistory,
    this.description,
    this.targetMilli,
    this.targetUnit,
    this.stopwatchEnabled = false,
    this.showOnDashboard = true,
    this.checklistItems = const [],
    this.archived = false,
    this.sortOrder = 0,
    this.systemKey,
  });

  final String id;
  final String name;
  final String? description;
  final String category;
  final String iconKey;
  final TrackingType trackingType;
  final ActivityPriority priority;

  /// Thousandths of [targetUnit] for counts and numbers; milliseconds for
  /// durations. Null means any log completes the occurrence.
  final int? targetMilli;
  final String? targetUnit;
  final ScheduleRule schedule;

  /// Every rule this activity has had, oldest first, each with the day it
  /// started. The last entry is [schedule].
  final List<ScheduleChange> scheduleHistory;
  final bool stopwatchEnabled;
  final bool showOnDashboard;
  final List<ChecklistItem> checklistItems;
  final bool archived;
  final int sortOrder;

  /// Set for routines the app created, such as `hygiene.bath`.
  final String? systemKey;

  bool get isEssential => priority == ActivityPriority.essential;

  /// The rule in force on [day]; null before the activity's first schedule.
  ScheduleRule? ruleOn(LocalDate day) {
    ScheduleRule? rule;
    for (final change in scheduleHistory) {
      if (change.from.isAfter(day)) break;
      rule = change.rule;
    }
    return rule;
  }

  /// This activity with [rule] applying from [from] onwards. Earlier days keep
  /// their rules; a change already starting on [from] or later is replaced.
  Activity rescheduled(ScheduleRule rule, {required LocalDate from}) => copyWith(
    schedule: rule,
    scheduleHistory: [
      ...scheduleHistory.where((c) => c.from.isBefore(from)),
      ScheduleChange(from: from, rule: rule),
    ],
  );

  /// Machine codes for invalid values; empty when the activity can be saved.
  List<String> get problems => [
    if (name.trim().isEmpty) 'name_required',
    if (name.trim().length > 80) 'name_too_long',
    ...schedule.problems,
    if (targetMilli != null && targetMilli! <= 0) 'target_out_of_range',
    if (trackingType == TrackingType.checklist && checklistItems.isEmpty) 'checklist_empty',
    if (checklistItems.any((i) => i.label.trim().isEmpty)) 'checklist_item_empty',
  ];

  Activity copyWith({
    String? name,
    String? Function()? description,
    String? category,
    String? iconKey,
    TrackingType? trackingType,
    ActivityPriority? priority,
    int? Function()? targetMilli,
    String? Function()? targetUnit,
    ScheduleRule? schedule,
    List<ScheduleChange>? scheduleHistory,
    bool? stopwatchEnabled,
    bool? showOnDashboard,
    List<ChecklistItem>? checklistItems,
    bool? archived,
    int? sortOrder,
    String? id,
  }) => Activity(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description == null ? this.description : description(),
    category: category ?? this.category,
    iconKey: iconKey ?? this.iconKey,
    trackingType: trackingType ?? this.trackingType,
    priority: priority ?? this.priority,
    targetMilli: targetMilli == null ? this.targetMilli : targetMilli(),
    targetUnit: targetUnit == null ? this.targetUnit : targetUnit(),
    schedule: schedule ?? this.schedule,
    scheduleHistory: scheduleHistory ?? this.scheduleHistory,
    stopwatchEnabled: stopwatchEnabled ?? this.stopwatchEnabled,
    showOnDashboard: showOnDashboard ?? this.showOnDashboard,
    checklistItems: checklistItems ?? this.checklistItems,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
    systemKey: systemKey,
  );
}

enum ActivityLogStatus {
  completed('completed'),
  skipped('skipped');

  const ActivityLogStatus(this.code);
  final String code;
  static ActivityLogStatus fromCode(String code) => values.firstWhere((s) => s.code == code);
}

enum LogSource {
  manual('manual'),
  notification('notification'),
  timer('timer');

  const LogSource(this.code);
  final String code;
  static LogSource fromCode(String code) => values.firstWhere((s) => s.code == code);
}

final class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.activityId,
    required this.status,
    required this.occurredAt,
    required this.localDate,
    required this.source,
    this.scheduledSlot,
    this.countValue,
    this.numericValueMilli,
    this.unit,
    this.durationS,
    this.checklistDone,
    this.notes,
  });

  final String id;
  final String activityId;
  final ActivityLogStatus status;
  final DateTime occurredAt;
  final LocalDate localDate;
  final LogSource source;

  /// The scheduled time (minutes after midnight) this log answers.
  final int? scheduledSlot;
  final int? countValue;
  final int? numericValueMilli;
  final String? unit;
  final int? durationS;
  final Set<String>? checklistDone;
  final String? notes;

  /// The amount this log adds towards a target, in the target's units.
  int amountMilli(TrackingType type) => switch (type) {
    TrackingType.count => (countValue ?? 0) * 1000,
    TrackingType.numeric => numericValueMilli ?? 0,
    TrackingType.duration || TrackingType.stopwatch => (durationS ?? 0) * 1000,
    _ => 0,
  };
}
