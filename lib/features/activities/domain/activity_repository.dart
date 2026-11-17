import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';
import 'activity.dart';

/// What the user enters when logging; the repository fills in ids and times.
final class LogDraft {
  const LogDraft({
    required this.status,
    required this.occurredAt,
    this.source = LogSource.manual,
    this.scheduledSlot,
    this.countValue,
    this.numericValueMilli,
    this.unit,
    this.durationS,
    this.checklistDone,
    this.notes,
  });

  final ActivityLogStatus status;
  final DateTime occurredAt;
  final LogSource source;
  final int? scheduledSlot;
  final int? countValue;
  final int? numericValueMilli;
  final String? unit;
  final int? durationS;
  final Set<String>? checklistDone;
  final String? notes;
}

/// Ordinary activities and their logs (§5.14). Private activities use a
/// separate store in Phase 5 (decision C5).
abstract interface class ActivityRepository {
  /// Saves a new activity; its id is generated and its schedule starts today.
  Future<Result<Activity>> create(Activity draft);

  /// Saves changes. A new schedule applies from [scheduleFrom] (today by
  /// default), so past days keep their states. A tracking-type change that
  /// would invalidate existing logs is refused.
  Future<Result<void>> update(Activity activity, {LocalDate? scheduleFrom});

  Future<Result<Activity>> duplicate(String id, {required String name});
  Future<Result<void>> setArchived(String id, {required bool archived});

  /// Deletes the activity and its history.
  Future<Result<void>> delete(String id);

  /// Stores [orderedIds] as the new order.
  Future<Result<void>> reorder(List<String> orderedIds);

  Stream<List<Activity>> watchAll();
  Future<Activity?> byId(String id);

  Future<Result<ActivityLog>> addLog(String activityId, LogDraft draft);
  Future<Result<void>> updateLog(String logId, LogDraft draft);
  Future<Result<void>> deleteLog(String logId);

  /// Logs of every activity on the days [from] to [to], both included.
  Stream<List<ActivityLog>> watchLogsBetween(LocalDate from, LocalDate to);

  /// One activity's logs, newest first.
  Stream<List<ActivityLog>> watchLogsFor(String activityId, {int limit = 50});
  Future<bool> hasLogs(String activityId);
}
